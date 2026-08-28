import 'dart:async';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Callback when an inertial tap (temple/visor tap) is detected.
typedef OnInertialTapCallback = void Function();

/// Configuration for the inertial head/visor tap detector.
class InertialTapConfig {
  /// Minimum jerk (derivative of acceleration in m/s³) threshold for a tap.
  final double jerkThreshold;

  /// Cooldown between consecutive single taps to prevent false multiple triggers.
  final Duration tapCooldown;

  /// Maximum delay between two taps to register as a double-tap.
  final Duration doubleTapWindow;

  const InertialTapConfig({
    this.jerkThreshold = 18.0,
    this.tapCooldown = const Duration(milliseconds: 250),
    this.doubleTapWindow = const Duration(milliseconds: 400),
  });
}

/// Zero-accessory, zero-latency mechanical trigger that detects physical taps
/// on the side of the VR visor or the user's temple using the phone's accelerometer.
///
/// Enables instant "Gaze + Tap" selection without requiring hand gestures in front
/// of the camera or waiting for passive gaze dwell timers.
class InertialTapDetector {
  final InertialTapConfig config;

  OnInertialTapCallback? onSingleTap;
  OnInertialTapCallback? onDoubleTap;

  StreamSubscription<UserAccelerometerEvent>? _subscription;

  double _prevAx = 0.0;
  double _prevAy = 0.0;
  double _prevAz = 0.0;
  DateTime _lastEventTime = DateTime.now();
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _firstTapInWindow = DateTime.fromMillisecondsSinceEpoch(0);
  int _tapCount = 0;

  bool get isActive => _subscription != null;

  InertialTapDetector({
    this.config = const InertialTapConfig(),
    this.onSingleTap,
    this.onDoubleTap,
  });

  /// Starts listening to high-frequency linear accelerometer events.
  void start() {
    if (_subscription != null) return;

    _subscription = userAccelerometerEventStream().listen((event) {
      final now = DateTime.now();
      final dt = now.difference(_lastEventTime).inMicroseconds / 1000000.0;
      _lastEventTime = now;

      if (dt <= 0.001 || dt > 0.1) {
        _prevAx = event.x;
        _prevAy = event.y;
        _prevAz = event.z;
        return;
      }

      // Calculate 3D jerk (rate of change of linear acceleration)
      final dAx = (event.x - _prevAx) / dt;
      final dAy = (event.y - _prevAy) / dt;
      final dAz = (event.z - _prevAz) / dt;
      final jerkMagnitude = (dAx * dAx + dAy * dAy + dAz * dAz);

      _prevAx = event.x;
      _prevAy = event.y;
      _prevAz = event.z;

      // Check if jerk exceeds impact threshold (mechanical tap shockwave)
      if (jerkMagnitude > (config.jerkThreshold * config.jerkThreshold)) {
        final timeSinceLastTap = now.difference(_lastTapTime);
        if (timeSinceLastTap < config.tapCooldown) {
          return; // Suppress bounce reverberation
        }

        _lastTapTime = now;
        _handleTapEvent(now);
      }
    });
  }

  void _handleTapEvent(DateTime now) {
    HapticFeedback.lightImpact();

    if (_tapCount == 0 || now.difference(_firstTapInWindow) > config.doubleTapWindow) {
      _tapCount = 1;
      _firstTapInWindow = now;

      // Schedule single tap callback if no second tap arrives
      Timer(config.doubleTapWindow, () {
        if (_tapCount == 1) {
          onSingleTap?.call();
          _tapCount = 0;
        }
      });
    } else {
      // Second tap arrived within window -> Double Tap!
      _tapCount = 0;
      onDoubleTap?.call();
    }
  }

  /// Stops listening to accelerometer events.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
  }
}
