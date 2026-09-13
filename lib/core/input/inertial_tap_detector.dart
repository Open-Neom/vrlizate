import 'dart:async';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'vr_sensor_capabilities.dart';

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

/// Zero-accessory mechanical trigger that detects physical taps
/// on the side of the VR visor or the user's temple using the phone's accelerometer.
///
/// Single taps are immediate when no double-tap callback is configured. When
/// both gestures are enabled, a single tap waits for [InertialTapConfig.doubleTapWindow]
/// to distinguish it from a double tap.
class InertialTapDetector {
  final InertialTapConfig config;
  final Stream<UserAccelerometerEvent>? accelerometerStreamOverride;

  OnInertialTapCallback? onSingleTap;
  OnInertialTapCallback? onDoubleTap;

  StreamSubscription<UserAccelerometerEvent>? _subscription;
  Timer? _singleTapTimer;

  double _prevAx = 0.0;
  double _prevAy = 0.0;
  double _prevAz = 0.0;
  DateTime? _lastEventTime;
  DateTime? _lastTapTime;
  DateTime? _firstTapInWindow;
  int _tapCount = 0;
  int _session = 0;

  bool get isActive => _subscription != null;

  /// Custom sensor streams remain supported on hosts without a native plugin.
  bool get canStart =>
      accelerometerStreamOverride != null ||
      VrSensorCapabilities.supportsDeviceMotion;

  InertialTapDetector({
    this.config = const InertialTapConfig(),
    this.onSingleTap,
    this.onDoubleTap,
    this.accelerometerStreamOverride,
  });

  /// Starts listening to high-frequency linear accelerometer events.
  void start() {
    if (_subscription != null) return;
    if (!canStart) return;
    final session = ++_session;
    _lastEventTime = null;
    _lastTapTime = null;
    _firstTapInWindow = null;
    _tapCount = 0;

    _subscription =
        (accelerometerStreamOverride ??
                userAccelerometerEventStream(
                  samplingPeriod: SensorInterval.gameInterval,
                ))
            .listen(
              (event) {
                if (session != _session ||
                    !event.x.isFinite ||
                    !event.y.isFinite ||
                    !event.z.isFinite) {
                  return;
                }
                final now = event.timestamp;
                final previous = _lastEventTime;
                if (previous != null && !now.isAfter(previous)) return;
                final dt = previous == null
                    ? 0.0
                    : now.difference(previous).inMicroseconds / 1000000.0;
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
                if (jerkMagnitude >
                    (config.jerkThreshold * config.jerkThreshold)) {
                  final previousTap = _lastTapTime;
                  if (previousTap != null &&
                      now.difference(previousTap) < config.tapCooldown) {
                    return; // Suppress bounce reverberation
                  }

                  _lastTapTime = now;
                  _handleTapEvent(now);
                }
              },
              onError: (Object error) {
                if (session == _session) stop();
              },
              onDone: () {
                if (session == _session) stop();
              },
            );
  }

  void _handleTapEvent(DateTime now) {
    HapticFeedback.lightImpact();

    if (onDoubleTap == null) {
      onSingleTap?.call();
      return;
    }

    if (_tapCount == 0 ||
        now.difference(_firstTapInWindow!) > config.doubleTapWindow) {
      _tapCount = 1;
      _firstTapInWindow = now;

      _singleTapTimer?.cancel();
      final session = _session;
      // Schedule single tap callback if no second tap arrives
      _singleTapTimer = Timer(config.doubleTapWindow, () {
        if (session == _session && _tapCount == 1) {
          onSingleTap?.call();
          _tapCount = 0;
        }
      });
    } else {
      // Second tap arrived within window -> Double Tap!
      _singleTapTimer?.cancel();
      _singleTapTimer = null;
      _tapCount = 0;
      onDoubleTap?.call();
    }
  }

  /// Stops listening to accelerometer events.
  void stop() {
    _session++;
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _tapCount = 0;
    _lastEventTime = null;
    _lastTapTime = null;
    _firstTapInWindow = null;
  }

  void dispose() {
    stop();
  }
}
