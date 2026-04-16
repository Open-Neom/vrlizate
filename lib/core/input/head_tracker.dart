import 'dart:async';

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
  double _offsetX = 0;
  double _offsetY = 0;
  bool _calibrating = false;
  int _calibrationSamples = 0;
  double _calibrationSumX = 0;
  double _calibrationSumY = 0;

  HeadTracker({required this.target, this.sensitivity = 0.03});

  /// For backwards compatibility with VRCamera.
  factory HeadTracker.forCamera(dynamic camera, {double sensitivity = 0.03}) {
    return HeadTracker(
      target: _DynamicTarget(camera),
      sensitivity: sensitivity,
    );
  }

  /// Starts gyroscope tracking. Calls [calibrate] automatically.
  void start() {
    if (kIsWeb) return;
    stop();
    calibrate();

    _subscription = gyroscopeEventStream().listen((event) {
      if (_calibrating) {
        _calibrationSumX += event.x;
        _calibrationSumY += event.y;
        _calibrationSamples++;
        return;
      }

      final adjustedX = event.x - _offsetX;
      final adjustedY = event.y - _offsetY;

      // Landscape mapping:
      // Negate X for correct left/right direction
      // Amplify Y (pitch) so user can reach 90° up/down without straining neck
      target.rotate(-adjustedX * sensitivity, adjustedY * sensitivity * 1.8);
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
