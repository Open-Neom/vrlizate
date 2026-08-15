import 'dart:math' as math;
import 'dart:typed_data';

/// Gestures detectable through active ultrasonic sensing (speaker emits an
/// inaudible tone, the microphone listens to the hand's echo).
enum UltrasonicGesture {
  /// Hand moving towards the device (positive Doppler shift).
  push,

  /// Hand moving away from the device (negative Doppler shift).
  pull,

  /// Hand entering the sensing zone (broadband echo energy rise).
  hoverEnter,

  /// Hand leaving the sensing zone.
  hoverExit,
}

/// An event emitted by [UltrasonicGestureChannel].
class UltrasonicGestureEvent {
  final UltrasonicGesture gesture;

  /// Estimated signed Doppler shift in Hz at detection time
  /// (positive = approaching).
  final double dopplerHz;

  /// Echo energy relative to the noise floor (1.0 = at floor).
  final double strength;

  final DateTime timestamp;

  UltrasonicGestureEvent({
    required this.gesture,
    this.dopplerHz = 0,
    this.strength = 1.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Configuration for the ultrasonic sensing channel.
class UltrasonicGestureConfig {
  /// Audio sample rate of the microphone stream (Hz).
  final int sampleRate;

  /// Frequency of the emitted tone (Hz). 18–20 kHz is inaudible for most
  /// adults and reproducible by commodity speakers.
  final double carrierFrequency;

  /// FFT window size in samples (power of two). 1024 @ 48 kHz ≈ 21 ms
  /// of latency per analysis frame.
  final int fftSize;

  /// Half-bandwidth around the carrier analysed for Doppler (Hz).
  final double bandwidth;

  /// Minimum echo-energy ratio over the noise floor to consider a hand
  /// present (linear, not dB).
  final double presenceThreshold;

  /// Minimum |Doppler| shift (Hz) to trigger a push/pull gesture.
  final double dopplerThreshold;

  /// Cooldown between two push/pull events.
  final Duration gestureCooldown;

  const UltrasonicGestureConfig({
    this.sampleRate = 48000,
    this.carrierFrequency = 19000,
    this.fftSize = 1024,
    this.bandwidth = 1200,
    this.presenceThreshold = 1.8,
    this.dopplerThreshold = 120,
    this.gestureCooldown = const Duration(milliseconds: 350),
  });
}

/// Active-ultrasonic hand gesture channel (FingerIO / LLAP / AudioGest
/// family): the device speaker emits an inaudible tone and hand motion near
/// the microphone is detected from the Doppler-shifted echo.
///
/// The package performs the sensing DSP only. The host app must:
/// 1. Play the tone returned by [generateTone] in a loop (e.g. with an
///    audio plugin configured for low-latency PCM output).
/// 2. Capture microphone PCM (e.g. with a recording plugin) and feed it
///    through [feedPcm].
///
/// Works in the dark and with the headset cover closed — complementary to
/// camera-based hand tracking.
class UltrasonicGestureChannel {
  final UltrasonicGestureConfig config;

  /// Called for each recognized ultrasonic gesture.
  void Function(UltrasonicGestureEvent event)? onGesture;

  final List<double> _buffer = [];
  final _Fft _fft;

  /// Current noise floor estimate of the analysis band (linear energy).
  double get noiseFloor => _noiseFloor;
  double _noiseFloor = 1e-9;

  /// Whether a hand is currently present in the sensing zone.
  bool get handPresent => _handPresent;
  bool _handPresent = false;

  /// Last signed Doppler estimate in Hz (debug / UI).
  double get lastDopplerHz => _lastDopplerHz;
  double _lastDopplerHz = 0;

  DateTime? _lastGestureTime;

  UltrasonicGestureChannel({this.config = const UltrasonicGestureConfig()})
    : _fft = _Fft(config.fftSize);

  /// Generates PCM samples of the inaudible carrier tone to be looped by the
  /// host app's audio output.
  List<double> generateTone(int numSamples) {
    final w = 2 * math.pi * config.carrierFrequency / config.sampleRate;
    return List<double>.generate(numSamples, (n) => 0.6 * math.sin(w * n));
  }

  /// Feeds raw mono PCM samples (-1..1) captured from the microphone.
  void feedPcm(List<double> samples) {
    _buffer.addAll(samples);
    while (_buffer.length >= config.fftSize) {
      final window = _buffer.sublist(0, config.fftSize);
      _buffer.removeRange(0, config.fftSize);
      _analyze(window);
    }
  }

  void _analyze(List<double> samples) {
    final spectrum = _fft.magnitudeSpectrum(samples, hannWindow: true);
    final binHz = config.sampleRate / config.fftSize;
    final carrierBin = config.carrierFrequency / binHz;
    final bandBins = (config.bandwidth / binHz).round();

    final lowerStart = (carrierBin - bandBins).floor().clamp(
      1,
      spectrum.length - 1,
    );
    final carrierIdx = carrierBin.round().clamp(1, spectrum.length - 1);
    final upperEnd = (carrierBin + bandBins).ceil().clamp(
      1,
      spectrum.length - 1,
    );

    // Leakage guard: skip bins immediately adjacent to the carrier itself.
    final guard = (30 / binHz).ceil().clamp(1, bandBins);

    var lowerEnergy = 0.0;
    for (var i = lowerStart; i < carrierIdx - guard; i++) {
      lowerEnergy += spectrum[i] * spectrum[i];
    }
    var upperEnergy = 0.0;
    for (var i = carrierIdx + guard; i <= upperEnd; i++) {
      upperEnergy += spectrum[i] * spectrum[i];
    }

    final total = lowerEnergy + upperEnergy;

    // Track the noise floor with a slow asymmetric filter: fast down (adapt
    // to quieter rooms), slow up (do not chase the gesture's own energy).
    if (!_handPresent) {
      _noiseFloor = total < _noiseFloor
          ? total
          : _noiseFloor * 0.995 + total * 0.005;
    }

    final strength = total / math.max(_noiseFloor, 1e-12);

    // Signed Doppler estimate from sideband imbalance.
    final doppler = total > 1e-12
        ? (upperEnergy - lowerEnergy) / total * config.bandwidth
        : 0.0;
    _lastDopplerHz = doppler;

    // Presence transitions.
    final present = strength >= config.presenceThreshold;
    if (present && !_handPresent) {
      _handPresent = true;
      _emit(UltrasonicGesture.hoverEnter, doppler, strength);
      return;
    }
    if (!present && _handPresent) {
      _handPresent = false;
      _emit(UltrasonicGesture.hoverExit, doppler, strength);
      return;
    }
    if (!_handPresent) return;

    // Motion gestures with cooldown.
    final now = DateTime.now();
    final last = _lastGestureTime;
    if (last != null && now.difference(last) < config.gestureCooldown) return;

    if (doppler > config.dopplerThreshold) {
      _lastGestureTime = now;
      _emit(UltrasonicGesture.push, doppler, strength);
    } else if (doppler < -config.dopplerThreshold) {
      _lastGestureTime = now;
      _emit(UltrasonicGesture.pull, doppler, strength);
    }
  }

  void _emit(UltrasonicGesture gesture, double doppler, double strength) {
    onGesture?.call(
      UltrasonicGestureEvent(
        gesture: gesture,
        dopplerHz: doppler,
        strength: strength,
      ),
    );
  }

  /// Resets noise-floor and presence state (e.g. when the tone restarts).
  void reset() {
    _buffer.clear();
    _noiseFloor = 1e-9;
    _handPresent = false;
    _lastDopplerHz = 0;
    _lastGestureTime = null;
  }

  void dispose() => reset();
}

/// Iterative radix-2 FFT over real input.
class _Fft {
  final int size;
  final Float64List _re;
  final Float64List _im;
  late final List<int> _bitReverse;
  late final Float64List _hann;

  _Fft(this.size)
    : assert(size > 0 && (size & (size - 1)) == 0, 'size must be power of 2'),
      _re = Float64List(size),
      _im = Float64List(size) {
    final levels = (math.log(size) / math.ln2).round();
    _bitReverse = List<int>.generate(size, (i) {
      var r = 0;
      for (var b = 0; b < levels; b++) {
        r |= ((i >> b) & 1) << (levels - 1 - b);
      }
      return r;
    });
    _hann = Float64List.fromList(
      List<double>.generate(
        size,
        (n) => 0.5 * (1 - math.cos(2 * math.pi * n / (size - 1))),
      ),
    );
  }

  /// Returns the single-sided magnitude spectrum (size/2 bins).
  Float64List magnitudeSpectrum(List<double> input, {bool hannWindow = false}) {
    for (var i = 0; i < size; i++) {
      final src = _bitReverse[i];
      _re[i] = input[src] * (hannWindow ? _hann[src] : 1.0);
      _im[i] = 0;
    }

    for (var block = 2; block <= size; block *= 2) {
      final half = block ~/ 2;
      final step = size ~/ block;
      for (var start = 0; start < size; start += block) {
        for (var k = 0; k < half; k++) {
          final angle = -2 * math.pi * k / block;
          final wr = math.cos(angle);
          final wi = math.sin(angle);
          final even = start + k;
          final odd = start + k + half;
          final tr = wr * _re[odd] - wi * _im[odd];
          final ti = wr * _im[odd] + wi * _re[odd];
          _re[odd] = _re[even] - tr;
          _im[odd] = _im[even] - ti;
          _re[even] += tr;
          _im[even] += ti;
          // step is implicit via bit reversal; kept for clarity.
          assert(step > 0);
        }
      }
    }

    final out = Float64List(size ~/ 2);
    for (var i = 0; i < size ~/ 2; i++) {
      out[i] = math.sqrt(_re[i] * _re[i] + _im[i] * _im[i]) / size;
    }
    return out;
  }
}
