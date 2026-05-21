import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sensors_plus/sensors_plus.dart';

/// Interface for anything that can receive rotation input.
abstract class RotationTarget {
  void rotate(double dTheta, double dPhi);
  void reset();
}

/// Head tracking input via device gyroscope with calibration.
class HeadTracker {
  final RotationTarget target;

  /// Sensitivity multiplier for gyroscope input.
  double sensitivity;

  /// Whether gyroscope is available and active.
  bool get isActive => _subscription != null;

  StreamSubscription<GyroscopeEvent>? _subscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  static const double _alpha = 0.98;

  double _offsetX = 0;
  double _offsetY = 0;
  bool _calibrating = false;
  int _calibrationSamples = 0;
  double _calibrationSumX = 0;
  double _calibrationSumY = 0;

  // Running fused states
  double _pitchFused = 0.0;
  double _rollFused = 0.0;
  double? _prevPitchFused;
  double? _prevRollFused;

  // Latest accelerometer readings
  double _accelX = 0.0;
  double _accelY = 0.0;
  double _accelZ = 9.8;

  DateTime? _lastTimestamp;

  final Stream<GyroscopeEvent>? gyroscopeStreamOverride;
  final Stream<AccelerometerEvent>? accelerometerStreamOverride;

  HeadTracker({
    required this.target,
    this.sensitivity = 0.03,
    this.gyroscopeStreamOverride,
    this.accelerometerStreamOverride,
  });

  /// For backwards compatibility with VRCamera.
  factory HeadTracker.forCamera(
    dynamic camera, {
    double sensitivity = 0.03,
    Stream<GyroscopeEvent>? gyroscopeStreamOverride,
    Stream<AccelerometerEvent>? accelerometerStreamOverride,
  }) {
    return HeadTracker(
      target: _DynamicTarget(camera),
      sensitivity: sensitivity,
      gyroscopeStreamOverride: gyroscopeStreamOverride,
      accelerometerStreamOverride: accelerometerStreamOverride,
    );
  }

  /// Starts gyroscope tracking. Calls [calibrate] automatically.
  void start() {
    if (kIsWeb) return;
    stop();
    calibrate();

    _lastTimestamp = null;
    _prevPitchFused = null;
    _prevRollFused = null;
    _pitchFused = 0.0;
    _rollFused = 0.0;

    _accelSubscription = (accelerometerStreamOverride ?? accelerometerEventStream()).listen((event) {
      _accelX = event.x;
      _accelY = event.y;
      _accelZ = event.z;
    });

    _subscription = (gyroscopeStreamOverride ?? gyroscopeEventStream()).listen((event) {
      if (_calibrating) {
        _calibrationSumX += event.x;
        _calibrationSumY += event.y;
        _calibrationSamples++;
        return;
      }

      final adjustedX = event.x - _offsetX;
      final adjustedY = event.y - _offsetY;

      final now = DateTime.now();
      if (_lastTimestamp == null) {
        _lastTimestamp = now;
        final accelPitch = atan2(_accelY, _accelZ);
        final accelRoll = atan2(-_accelX, sqrt(_accelY * _accelY + _accelZ * _accelZ));
        _pitchFused = accelPitch;
        _rollFused = accelRoll;
        _prevPitchFused = accelPitch;
        _prevRollFused = accelRoll;
        return;
      }

      final dt = now.difference(_lastTimestamp!).inMicroseconds / 1000000.0;
      _lastTimestamp = now;

      // 1. Calculate absolute pitch/roll from accelerometer gravity vector
      final accelPitch = atan2(_accelY, _accelZ);
      final accelRoll = atan2(-_accelX, sqrt(_accelY * _accelY + _accelZ * _accelZ));

      // 2. Blend accelerometer and integrated gyroscope values using Complementary Filter
      _pitchFused = _alpha * (_pitchFused + adjustedX * dt) + (1 - _alpha) * accelPitch;
      _rollFused = _alpha * (_rollFused + adjustedY * dt) + (1 - _alpha) * accelRoll;

      // 3. Compute delta movements
      final dPitchFused = _pitchFused - (_prevPitchFused ?? _pitchFused);
      final dRollFused = _rollFused - (_prevRollFused ?? _rollFused);

      _prevPitchFused = _pitchFused;
      _prevRollFused = _rollFused;

      // 4. Forward as landscape rotations (Yaw, Pitch)
      target.rotate(-dPitchFused * sensitivity, dRollFused * sensitivity * 1.8);
    });
  }

  /// Calibrates gyroscope by averaging drift over 1 second.
  void calibrate() {
    _calibrating = true;
    _calibrationSamples = 0;
    _calibrationSumX = 0;
    _calibrationSumY = 0;

    Future.delayed(const Duration(seconds: 1), () {
      if (_calibrationSamples > 0) {
        _offsetX = _calibrationSumX / _calibrationSamples;
        _offsetY = _calibrationSumY / _calibrationSamples;
      }
      _calibrating = false;
    });
  }

  /// Applies touch/pan input as rotation (fallback when no gyroscope).
  void applyTouchDelta(
    double dx,
    double dy, {
    double touchSensitivity = 0.005,
  }) {
    target.rotate(-dx * touchSensitivity, -dy * touchSensitivity);
  }

  /// Stops gyroscope tracking.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _accelSubscription?.cancel();
    _accelSubscription = null;
  }

  void dispose() {
    stop();
  }
}

/// Wraps any object with rotate/reset methods dynamically.
class _DynamicTarget implements RotationTarget {
  final dynamic _target;
  _DynamicTarget(this._target);

  @override
  void rotate(double dTheta, double dPhi) {
    _target.rotate(dTheta, dPhi);
  }

  @override
  void reset() {
    _target.reset();
  }
}
