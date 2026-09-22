import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'vr_controller_protocol.dart';

/// Monotonic clock used by [VrRemotePosePredictor].
typedef VrPoseClock = int Function();

/// Opt-in One Euro smoothing for a remote IMU orientation, before prediction.
///
/// Uses the same speed-adaptive cutoff as the landmark `OneEuroFilter`, but
/// measures angular speed and interpolates unit quaternions along their short
/// arc. This does not filter the visor, touch laser, buttons or stick inputs.
/// Tune on the target controller: lower cutoff removes more stationary jitter
/// but delays movement; higher [beta] reduces that delay during fast motion.
class VrRemotePoseSmoothing {
  VrRemotePoseSmoothing({
    this.minCutoff = 1,
    this.beta = .02,
    this.derivativeCutoff = 1,
    this.resetAfter = const Duration(milliseconds: 250),
    this.discontinuityRadians = math.pi / 2,
  }) {
    for (final parameter in [
      ('minCutoff', minCutoff),
      ('derivativeCutoff', derivativeCutoff),
    ]) {
      if (!parameter.$2.isFinite || parameter.$2 <= 0) {
        throw ArgumentError.value(
          parameter.$2,
          parameter.$1,
          'Must be finite and positive.',
        );
      }
    }
    if (!beta.isFinite || beta < 0) {
      throw ArgumentError.value(
        beta,
        'beta',
        'Must be finite and nonnegative.',
      );
    }
    if (resetAfter <= Duration.zero) {
      throw ArgumentError.value(resetAfter, 'resetAfter', 'Must be positive.');
    }
    if (!discontinuityRadians.isFinite ||
        discontinuityRadians <= 0 ||
        discontinuityRadians > math.pi) {
      throw ArgumentError.value(
        discontinuityRadians,
        'discontinuityRadians',
        'Must be in (0, pi].',
      );
    }
  }

  /// Stationary cutoff and derivative cutoff in Hz.
  final double minCutoff, derivativeCutoff;

  /// Adds cutoff Hz per radian/second of smoothed angular speed.
  final double beta;

  /// A longer gap restarts at the new pose instead of dragging an old pose.
  final Duration resetAfter;

  /// A single-sample angular jump larger than this restarts the filter, as
  /// after a controller recenter. Quaternion sign changes are not jumps.
  final double discontinuityRadians;
}

/// Allocation-free angular pose prediction for a networked 3DoF controller.
///
/// Prediction compensates for half the measured round-trip time, time elapsed
/// since the packet arrived, and a small configurable render lead. The result
/// is clamped so stale or noisy packets cannot produce an unbounded pose jump.
class VrRemotePosePredictor {
  final Duration renderLead;
  final Duration maximumPrediction;
  final double latencySmoothing;
  final VrPoseClock _clock;
  final _RemoteQuaternionFilter? _orientationFilter;

  final Quaternion _baseOrientation = Quaternion.identity();
  final Vector3 _angularVelocity = Vector3.zero();

  int _receivedAtMicroseconds = 0;
  double _roundTripLatencyMicroseconds = 0;
  int _lastPredictionHorizonMicroseconds = 0;
  bool _hasLatency = false;
  bool _hasPose = false;

  VrRemotePosePredictor({
    this.renderLead = const Duration(milliseconds: 8),
    this.maximumPrediction = const Duration(milliseconds: 80),
    this.latencySmoothing = 0.2,
    VrRemotePoseSmoothing? smoothing,
    VrPoseClock? clock,
  }) : _clock = clock ?? _MonotonicPoseClock().now,
       _orientationFilter = smoothing == null
           ? null
           : _RemoteQuaternionFilter(smoothing) {
    if (renderLead.isNegative) {
      throw ArgumentError.value(
        renderLead,
        'renderLead',
        'Must not be negative.',
      );
    }
    if (maximumPrediction.isNegative) {
      throw ArgumentError.value(
        maximumPrediction,
        'maximumPrediction',
        'Must not be negative.',
      );
    }
    if (!latencySmoothing.isFinite ||
        latencySmoothing <= 0 ||
        latencySmoothing > 1) {
      throw RangeError.range(
        latencySmoothing,
        0,
        1,
        'latencySmoothing',
        'Must be finite and in the range (0, 1].',
      );
    }
  }

  bool get hasPose => _hasPose;

  Duration get roundTripLatency =>
      Duration(microseconds: _roundTripLatencyMicroseconds.round());

  Duration get lastPredictionHorizon =>
      Duration(microseconds: _lastPredictionHorizonMicroseconds);

  /// Adds an RTT sample using an exponential moving average.
  void updateLatency(Duration roundTrip) {
    if (roundTrip.isNegative) {
      throw ArgumentError.value(
        roundTrip,
        'roundTrip',
        'Must not be negative.',
      );
    }
    final sample = roundTrip.inMicroseconds.toDouble();
    if (_hasLatency) {
      _roundTripLatencyMicroseconds +=
          (sample - _roundTripLatencyMicroseconds) * latencySmoothing;
    } else {
      _roundTripLatencyMicroseconds = sample;
      _hasLatency = true;
    }
  }

  /// Stores the most recent frame without retaining mutable frame objects.
  /// Optional smoothing uses local monotonic reception times; the sender's
  /// clock need not be synchronized with the visor. By default poses pass
  /// through unchanged, preserving existing input latency.
  void pushFrame(VrRemotePoseFrame frame, {int? receivedAtMicroseconds}) {
    final receivedAt = receivedAtMicroseconds ?? _clock();
    _baseOrientation.setValues(frame.qx, frame.qy, frame.qz, frame.qw);
    _baseOrientation.normalize();
    _orientationFilter?.filterInPlace(_baseOrientation, receivedAt);
    _angularVelocity.setValues(
      frame.angularVelocityX,
      frame.angularVelocityY,
      frame.angularVelocityZ,
    );
    _receivedAtMicroseconds = receivedAt;
    _hasPose = true;
  }

  /// Writes the predicted orientation into [out].
  ///
  /// The returned boolean is false until the first pose has been received.
  bool predictTo(Quaternion out, {int? atMicroseconds}) {
    if (!_hasPose) return false;

    final now = atMicroseconds ?? _clock();
    final age = math.max(0, now - _receivedAtMicroseconds);
    final oneWayLatency = _hasLatency
        ? (_roundTripLatencyMicroseconds * 0.5).round()
        : 0;
    final requestedHorizon = age + oneWayLatency + renderLead.inMicroseconds;
    _lastPredictionHorizonMicroseconds = requestedHorizon.clamp(
      0,
      maximumPrediction.inMicroseconds,
    );

    final dt = _lastPredictionHorizonMicroseconds / 1000000.0;
    _integrateTo(out, dt);
    return true;
  }

  void reset() {
    _orientationFilter?.reset();
    _baseOrientation.setValues(0, 0, 0, 1);
    _angularVelocity.setZero();
    _receivedAtMicroseconds = 0;
    _lastPredictionHorizonMicroseconds = 0;
    _hasPose = false;
  }

  void _integrateTo(Quaternion out, double dt) {
    final x = _angularVelocity.x;
    final y = _angularVelocity.y;
    final z = _angularVelocity.z;
    final speed = math.sqrt(x * x + y * y + z * z);
    if (speed <= 1e-8 || dt <= 0) {
      out.setFrom(_baseOrientation);
      return;
    }

    final halfAngle = speed * dt * 0.5;
    final scale = math.sin(halfAngle) / speed;
    final dx = x * scale;
    final dy = y * scale;
    final dz = z * scale;
    final dw = math.cos(halfAngle);
    final ox = _baseOrientation.x;
    final oy = _baseOrientation.y;
    final oz = _baseOrientation.z;
    final ow = _baseOrientation.w;

    // Sensor orientation followed by the angular delta: base * delta.
    out.setValues(
      ow * dx + ox * dw + oy * dz - oz * dy,
      ow * dy - ox * dz + oy * dw + oz * dx,
      ow * dz + ox * dy - oy * dx + oz * dw,
      ow * dw - ox * dx - oy * dy - oz * dz,
    );
    out.normalize();
  }
}

/// Quaternion adaptation of the package's One Euro cutoff equations.
/// Retains fixed storage and never averages quaternion components across
/// opposite hemispheres, where q and -q represent the same orientation.
final class _RemoteQuaternionFilter {
  _RemoteQuaternionFilter(this.settings);

  final VrRemotePoseSmoothing settings;
  final Quaternion _previousRaw = Quaternion.identity();
  final Quaternion _filtered = Quaternion.identity();
  int? _previousTime;
  double _speed = 0;

  void reset() {
    _previousTime = null;
    _speed = 0;
  }

  void _start(Quaternion pose, int now) {
    _previousRaw.setFrom(pose);
    _filtered.setFrom(pose);
    _previousTime = now;
    _speed = 0;
  }

  void filterInPlace(Quaternion pose, int now) {
    final previousTime = _previousTime;
    if (previousTime == null) {
      _start(pose, now);
      return;
    }
    final elapsed = now - previousTime;
    final rawDot = _normalizedDot(pose, _previousRaw).abs().clamp(0.0, 1.0);
    final angle = 2 * math.acos(rawDot);
    if (elapsed <= 0 ||
        elapsed > settings.resetAfter.inMicroseconds ||
        angle > settings.discontinuityRadians) {
      _start(pose, now);
      return;
    }
    final dt = elapsed / 1000000.0;
    final derivativeAlpha = _alpha(settings.derivativeCutoff, dt);
    _speed += (angle / dt - _speed) * derivativeAlpha;
    final alpha = _alpha(settings.minCutoff + settings.beta * _speed, dt);
    _previousRaw.setFrom(pose);
    _previousTime = now;

    var dot = _normalizedDot(_filtered, pose).clamp(-1.0, 1.0);
    final sign = dot < 0 ? -1.0 : 1.0;
    dot = dot.abs();
    var previousWeight = 1 - alpha;
    var nextWeight = alpha;
    if (dot < .9995) {
      final arc = math.acos(dot);
      final denominator = math.sin(arc);
      previousWeight = math.sin((1 - alpha) * arc) / denominator;
      nextWeight = math.sin(alpha * arc) / denominator;
    }
    nextWeight *= sign;
    _filtered.setValues(
      previousWeight * _filtered.x + nextWeight * pose.x,
      previousWeight * _filtered.y + nextWeight * pose.y,
      previousWeight * _filtered.z + nextWeight * pose.z,
      previousWeight * _filtered.w + nextWeight * pose.w,
    );
    _filtered.normalize();
    pose.setFrom(_filtered);
  }

  static double _dot(Quaternion a, Quaternion b) =>
      a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;

  // vector_math stores components in Float32 even after normalize(). Taking
  // acos of an uncorrected dot can turn that length error into phantom motion
  // (or a false discontinuity). Correct the norms in double precision first.
  static double _normalizedDot(Quaternion a, Quaternion b) =>
      _dot(a, b) / math.sqrt(_dot(a, a) * _dot(b, b));

  static double _alpha(double cutoff, double dt) =>
      1 / (1 + 1 / (2 * math.pi * cutoff * dt));
}

final class _MonotonicPoseClock {
  final int _epochStart = DateTime.now().microsecondsSinceEpoch;
  final Stopwatch _stopwatch = Stopwatch()..start();

  int now() => _epochStart + _stopwatch.elapsedMicroseconds;
}
