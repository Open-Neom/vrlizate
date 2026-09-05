import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'vr_controller_protocol.dart';

/// Monotonic clock used by [VrRemotePosePredictor].
typedef VrPoseClock = int Function();

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
    VrPoseClock? clock,
  }) : _clock = clock ?? _MonotonicPoseClock().now {
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
  void pushFrame(VrRemotePoseFrame frame, {int? receivedAtMicroseconds}) {
    _baseOrientation.setValues(frame.qx, frame.qy, frame.qz, frame.qw);
    _baseOrientation.normalize();
    _angularVelocity.setValues(
      frame.angularVelocityX,
      frame.angularVelocityY,
      frame.angularVelocityZ,
    );
    _receivedAtMicroseconds = receivedAtMicroseconds ?? _clock();
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

final class _MonotonicPoseClock {
  final int _epochStart = DateTime.now().microsecondsSinceEpoch;
  final Stopwatch _stopwatch = Stopwatch()..start();

  int now() => _epochStart + _stopwatch.elapsedMicroseconds;
}
