import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Deterministic animation curves, spring physics, envelopes, value noise,
/// Fritsch-Carlson monotone cubic splines, and beat-locked timelines.
///
/// Adapted from the Lemo-Opuscar procedural animation toolkit (MIT License).
abstract final class VrCurves {
  static const double tau = math.pi * 2.0;

  /// Clamps [x] to `[a, b]` (defaults to `0..1`).
  static double clamp01(double x, [double a = 0.0, double b = 1.0]) =>
      x < a ? a : (x > b ? b : x);

  /// Linearly interpolates between [a] and [b] by [t].
  static double lerp(double a, double b, double t) => a + (b - a) * t;

  /// Normalized segment ramp: maps `t` in `[a, b]` to `0..1`, clamped outside.
  static double seg(double t, double a, double b) {
    if (b == a) return t >= b ? 1.0 : 0.0;
    return clamp01((t - a) / (b - a));
  }

  /// Hermite smoothstep `3t^2 - 2t^3` on `0..1`.
  static double smoothstep(double t) {
    final u = clamp01(t);
    return u * u * (3.0 - 2.0 * u);
  }

  /// Cubic ease-in-out on `0..1`.
  static double easeInOutCubic(double t) {
    final u = clamp01(t);
    return u < 0.5
        ? 4.0 * u * u * u
        : 1.0 - math.pow(-2.0 * u + 2.0, 3) / 2.0;
  }

  /// Cubic ease-out on `0..1`.
  static double easeOutCubic(double t) =>
      1.0 - math.pow(1.0 - clamp01(t), 3).toDouble();

  /// Cubic ease-in on `0..1`.
  static double easeInCubic(double t) => math.pow(clamp01(t), 3).toDouble();

  /// Ease-out with subtle overshoot settle (`s` controls overshoot magnitude).
  static double backOut(double t, {double overshoot = 1.8}) {
    final u = clamp01(t) - 1.0;
    return 1.0 + u * u * ((overshoot + 1.0) * u + overshoot);
  }

  /// Analytical underdamped spring response `0 -> 1` with 1-2 natural rebounds.
  ///
  /// [stiffness] (`k`) controls oscillation speed and [damping] (`z`, `0..1`)
  /// controls how quickly rebounds settle.
  static double spring(
    double t, {
    double stiffness = 7.0,
    double damping = 0.35,
  }) {
    final u = math.max(0.0, t);
    final z = damping.clamp(0.0, 0.9999);
    final omega = stiffness * math.sqrt(1.0 - z * z) * 1.6;
    return 1.0 - math.exp(-z * stiffness * u) * math.cos(omega * u);
  }

  /// Smooth plateau envelope `0 -> 1 -> 0` over `[start, end]` with
  /// [fadeIn] and [fadeOut] durations.
  static double envelope(
    double t,
    double start,
    double end, {
    double fadeIn = 0.3,
    double fadeOut = 0.3,
  }) {
    final rise = fadeIn <= 0 ? (t >= start ? 1.0 : 0.0) : seg(t, start, start + fadeIn);
    final fall = fadeOut <= 0 ? (t <= end ? 1.0 : 0.0) : 1.0 - seg(t, end - fadeOut, end);
    return smoothstep(math.min(rise, fall));
  }

  /// Deterministic scalar hash in `[0, 1)`.
  static double hash(double n) {
    final v = math.sin(n * 127.1 + 311.7) * 43758.5453;
    return v - v.floorToDouble();
  }

  /// 1D smooth value noise in `[0, 1)` for organic camera/avatar micro-motion.
  static double vnoise(double x) {
    final i = x.floorToDouble();
    final f = x - i;
    final u = f * f * (3.0 - 2.0 * f);
    return lerp(hash(i), hash(i + 1.0), u);
  }
}

/// Deterministic Mulberry32 pseudo-random generator for repeatable procedural
/// worlds, particle motion, and animations.
class VrSeededRandom {
  VrSeededRandom(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  /// Returns a deterministic double in `[0, 1)`.
  double nextDouble() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _imul32(_state ^ (_state >>> 15), 1 | _state);
    t = (t + _imul32(t ^ (t >>> 7), 61 | t)) ^ t;
    t = (t ^ (t >>> 14)) & 0xFFFFFFFF;
    return t / 4294967296.0;
  }

  /// Returns a deterministic double in `[min, max)`.
  double nextRange(double min, double max) =>
      min + (max - min) * nextDouble();

  static int _imul32(int a, int b) {
    final ah = (a >>> 16) & 0xFFFF;
    final al = a & 0xFFFF;
    final bh = (b >>> 16) & 0xFFFF;
    final bl = b & 0xFFFF;
    return ((al * bl) + (((ah * bl + al * bh) & 0xFFFF) << 16)) & 0xFFFFFFFF;
  }
}

/// Fritsch-Carlson monotone cubic Hermite spline.
///
/// Unlike standard Catmull-Rom or natural cubic splines, this interpolator
/// preserves monotonicity between keyframes and never introduces false
/// overshoot at local extrema or flat holds.
class VrMonotoneSpline {
  factory VrMonotoneSpline(List<(double time, double value)> keys) {
    if (keys.isEmpty) {
      throw ArgumentError.value(keys, 'keys', 'At least one keyframe is required.');
    }
    final sorted = List<(double, double)>.from(keys)
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final n = sorted.length;
    final xs = List<double>.generate(n, (i) => sorted[i].$1, growable: false);
    final ys = List<double>.generate(n, (i) => sorted[i].$2, growable: false);
    if (n == 1) {
      return VrMonotoneSpline._(xs, ys, const <double>[0.0]);
    }

    final d = List<double>.filled(n - 1, 0.0);
    final m = List<double>.filled(n, 0.0);
    for (var i = 0; i < n - 1; i++) {
      final dt = xs[i + 1] - xs[i];
      if (dt <= 0) {
        throw ArgumentError.value(
          keys,
          'keys',
          'Keyframe times must be strictly increasing.',
        );
      }
      d[i] = (ys[i + 1] - ys[i]) / dt;
    }
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (var i = 1; i < n - 1; i++) {
      m[i] = (d[i - 1] * d[i] <= 0.0) ? 0.0 : (d[i - 1] + d[i]) * 0.5;
    }
    for (var i = 0; i < n - 1; i++) {
      if (d[i] == 0.0) {
        m[i] = 0.0;
        m[i + 1] = 0.0;
        continue;
      }
      final a = m[i] / d[i];
      final b = m[i + 1] / d[i];
      final s = a * a + b * b;
      if (s > 9.0) {
        final k = 3.0 / math.sqrt(s);
        m[i] = k * a * d[i];
        m[i + 1] = k * b * d[i];
      }
    }
    return VrMonotoneSpline._(xs, ys, m);
  }

  const VrMonotoneSpline._(this._xs, this._ys, this._tangents);

  final List<double> _xs;
  final List<double> _ys;
  final List<double> _tangents;

  double get startTime => _xs.first;
  double get endTime => _xs.last;

  /// Evaluates the spline at [t] (clamped to `[startTime, endTime]`).
  double evaluate(double t) {
    final n = _xs.length;
    if (n == 1 || t <= _xs.first) return _ys.first;
    if (t >= _xs.last) return _ys.last;

    var lo = 0;
    var hi = n - 2;
    while (lo <= hi) {
      final mid = (lo + hi) >>> 1;
      if (t < _xs[mid]) {
        hi = mid - 1;
      } else if (t > _xs[mid + 1]) {
        lo = mid + 1;
      } else {
        lo = mid;
        break;
      }
    }
    final i = lo.clamp(0, n - 2);
    final h = _xs[i + 1] - _xs[i];
    final u = (t - _xs[i]) / h;
    final u2 = u * u;
    final u3 = u2 * u;
    return (2.0 * u3 - 3.0 * u2 + 1.0) * _ys[i] +
        (u3 - 2.0 * u2 + u) * h * _tangents[i] +
        (-2.0 * u3 + 3.0 * u2) * _ys[i + 1] +
        (u3 - u2) * h * _tangents[i + 1];
  }
}

/// Multi-dimensional monotone keyframe track (`[[t, [v0, v1, ...]], ...]`).
class VrCurveTrack {
  factory VrCurveTrack(List<(double time, List<double> values)> keys) {
    if (keys.isEmpty) {
      throw ArgumentError.value(keys, 'keys', 'At least one keyframe is required.');
    }
    final dim = keys.first.$2.length;
    if (dim == 0) {
      throw ArgumentError.value(keys, 'keys', 'Keyframe value list cannot be empty.');
    }
    for (final k in keys) {
      if (k.$2.length != dim) {
        throw ArgumentError.value(
          keys,
          'keys',
          'All keyframes must have the same dimension ($dim).',
        );
      }
    }
    final splines = List<VrMonotoneSpline>.generate(
      dim,
      (channel) => VrMonotoneSpline(
        [for (final k in keys) (k.$1, k.$2[channel])],
      ),
      growable: false,
    );
    return VrCurveTrack._(dim, splines);
  }

  const VrCurveTrack._(this.dimension, this._splines);

  final int dimension;
  final List<VrMonotoneSpline> _splines;

  double get startTime => _splines.first.startTime;
  double get endTime => _splines.first.endTime;

  List<double> evaluate(double t) =>
      List<double>.generate(dimension, (i) => _splines[i].evaluate(t), growable: false);
}

/// 3D vector track backed by Fritsch-Carlson monotone cubic splines.
///
/// Ideal for VR camera paths, hand/prop trajectories, and UI panel transitions
/// that must hit exact waypoints without overshooting.
class VrVector3Track {
  factory VrVector3Track(List<(double time, Vector3 value)> keys) {
    final track = VrCurveTrack([
      for (final (t, v) in keys) (t, <double>[v.x, v.y, v.z]),
    ]);
    return VrVector3Track._(track);
  }

  const VrVector3Track._(this._track);

  final VrCurveTrack _track;

  double get startTime => _track.startTime;
  double get endTime => _track.endTime;

  Vector3 evaluate(double t) {
    final vals = _track.evaluate(t);
    return Vector3(vals[0], vals[1], vals[2]);
  }
}

/// A tempo-locked section inside a [VrBeatTimeline].
class VrTimelineSection {
  const VrTimelineSection({
    required this.id,
    required this.startTime,
    required this.bpm,
    required this.beats,
    this.beatsPerBar = 4,
  }) : assert(bpm > 0, 'BPM must be positive.'),
       assert(beats > 0, 'Beats must be positive.'),
       assert(beatsPerBar > 0, 'beatsPerBar must be positive.');

  final String id;
  final double startTime;
  final double bpm;
  final double beats;
  final int beatsPerBar;

  /// Duration of one beat in seconds (`60 / bpm`).
  double get beatDuration => 60.0 / bpm;

  /// Duration of one bar in seconds.
  double get barDuration => beatDuration * beatsPerBar;

  /// Total duration of this section in seconds.
  double get duration => beats * beatDuration;

  /// End timestamp of this section in seconds.
  double get endTime => startTime + duration;

  /// Converts a 0-based [beatOffset] within this section to absolute seconds.
  double timeAtBeat(double beatOffset) => startTime + beatOffset * beatDuration;

  /// Converts a 0-based [bar] and [beatInBar] within this section to seconds.
  double timeAtBar(int bar, [double beatInBar = 0.0]) =>
      timeAtBeat(bar * beatsPerBar + beatInBar);
}

/// Single source of truth for beat-locked VR animations, scene cues, and audio.
class VrBeatTimeline {
  VrBeatTimeline({
    required List<VrTimelineSection> sections,
    Map<String, (String sectionId, double beat)> hits = const {},
  }) : _sections = List<VrTimelineSection>.unmodifiable(sections),
       _byId = {for (final s in sections) s.id: s},
       _hits = Map.unmodifiable(hits);

  final List<VrTimelineSection> _sections;
  final Map<String, VrTimelineSection> _byId;
  final Map<String, (String sectionId, double beat)> _hits;

  List<VrTimelineSection> get sections => _sections;

  VrTimelineSection? sectionById(String id) => _byId[id];

  /// Returns the active section at [timeSeconds], or the nearest section.
  VrTimelineSection? sectionAt(double timeSeconds) {
    if (_sections.isEmpty) return null;
    for (final s in _sections) {
      if (timeSeconds >= s.startTime && timeSeconds <= s.endTime) {
        return s;
      }
    }
    return timeSeconds < _sections.first.startTime
        ? _sections.first
        : _sections.last;
  }

  /// Absolute timestamp in seconds for a named hit cue.
  double? hitTime(String hitId) {
    final hit = _hits[hitId];
    if (hit == null) return null;
    final sec = _byId[hit.$1];
    return sec?.timeAtBeat(hit.$2);
  }

  /// Fractional beat index within the active section at [timeSeconds].
  double beatInSectionAt(double timeSeconds) {
    final sec = sectionAt(timeSeconds);
    if (sec == null) return 0.0;
    return ((timeSeconds - sec.startTime) / sec.beatDuration).clamp(0.0, sec.beats);
  }

  /// Returns a `1 -> 0` exponential beat pulse at [timeSeconds] for rhythmic
  /// visual effects (lights, scale pulses, rhythm indicators).
  double beatPulseAt(double timeSeconds, {double decayBeats = 0.35}) {
    final sec = sectionAt(timeSeconds);
    if (sec == null || timeSeconds < sec.startTime || timeSeconds > sec.endTime) {
      return 0.0;
    }
    final beatPos = (timeSeconds - sec.startTime) / sec.beatDuration;
    final frac = beatPos - beatPos.floorToDouble();
    return math.exp(-frac / math.max(0.01, decayBeats));
  }
}
