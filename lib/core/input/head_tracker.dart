import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart';

import 'background_isolate.dart';

/// Interface for anything that can receive rotation input.
abstract class RotationTarget {
  void rotate(double dTheta, double dPhi);
  void reset();
  void recenter() => reset();
}

/// Head tracking input via device gyroscope with calibration and background Isolate.
class HeadTracker {
  final RotationTarget target;

  /// Sensitivity multiplier for gyroscope input.
  /// 1.0 (default) = true 1:1 head tracking. Values > 1 amplify rotation.
  double sensitivity;

  /// Ergonomic pitch multiplier so comfortable neck tilts (±40°) reach the full vertical range.
  double pitchGain;

  /// Latency prediction compensation in milliseconds.
  double predictionMs;

  /// Whether to use background Isolate for sensor fusion (default: !kIsWeb)
  final bool useIsolate;

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

  // Running fused states (for main thread web fallback)
  double _yawFused = 0.0;
  double _pitchFused = 0.0;
  double? _prevYawFused;
  double? _prevPitchFused;

  // Latest accelerometer readings
  double _accelX = 0.0;
  double _accelY = 0.0;
  double _accelZ = 9.8;

  // DSD (Dynamic Sensor Diagnostics) fallback states
  bool isGyroscopeActive = true;
  int _gyroEventsCount = 0;
  double _smoothPitch = 0.0;
  double _smoothRoll = 0.0;
  double? _lastAccelPitch;

  DateTime? _lastTimestamp;

  BackgroundIsolate? _fusionIsolate;
  // The worker's SendPort (typed dynamically to stay WASM-compatible).
  dynamic _isolateSendPort;

  // Damping states
  double _dampedDYaw = 0.0;
  double _dampedDPitch = 0.0;

  /// Whether high-frequency sensor jitter damping is active.
  bool jitterDamping;

  final Stream<GyroscopeEvent>? gyroscopeStreamOverride;
  final Stream<AccelerometerEvent>? accelerometerStreamOverride;

  HeadTracker({
    required this.target,
    this.sensitivity = 1.0,
    this.pitchGain = 1.25,
    this.predictionMs = 15.0,
    this.jitterDamping = true,
    bool? useIsolate,
    this.gyroscopeStreamOverride,
    this.accelerometerStreamOverride,
  }) : useIsolate = useIsolate ?? false;

  /// For backwards compatibility with VRCamera.
  factory HeadTracker.forCamera(
    dynamic camera, {
    double sensitivity = 1.0,
    double predictionMs = 15.0,
    bool? useIsolate,
    Stream<GyroscopeEvent>? gyroscopeStreamOverride,
    Stream<AccelerometerEvent>? accelerometerStreamOverride,
  }) {
    return HeadTracker(
      target: _DynamicTarget(camera),
      sensitivity: sensitivity,
      predictionMs: predictionMs,
      useIsolate: useIsolate,
      gyroscopeStreamOverride: gyroscopeStreamOverride,
      accelerometerStreamOverride: accelerometerStreamOverride,
    );
  }

  /// Starts gyroscope tracking. Calls [calibrate] automatically.
  void start() {
    stop();
    calibrate();

    _lastTimestamp = null;
    _prevYawFused = null;
    _prevPitchFused = null;
    _yawFused = 0.0;
    _pitchFused = 0.0;

    _gyroEventsCount = 0;
    isGyroscopeActive = true;
    _smoothPitch = 0.0;
    _smoothRoll = 0.0;
    _lastAccelPitch = null;

    // Detect if gyroscope is present and active within 800ms
    Future.delayed(const Duration(milliseconds: 800), () {
      if (_gyroEventsCount == 0) {
        isGyroscopeActive = false;
      }
    });

    if (!useIsolate) {
      // Main-thread Direct Low-Latency Fusion
      _accelSubscription =
          (accelerometerStreamOverride ??
                  accelerometerEventStream(
                    samplingPeriod: SensorInterval.fastestInterval,
                  ))
              .listen((event) {
                _accelX = event.x;
                _accelY = event.y;
                _accelZ = event.z;

                if (!isGyroscopeActive) {
                  _updateFromAccelerometerOnly(event.x, event.y, event.z);
                }
              });

      _subscription =
          (gyroscopeStreamOverride ??
                  gyroscopeEventStream(
                    samplingPeriod: SensorInterval.fastestInterval,
                  ))
              .listen((event) {
                _gyroEventsCount++;
                isGyroscopeActive = true;

                if (_calibrating) {
                  _calibrationSumX += event.x;
                  _calibrationSumY += event.y;
                  _calibrationSamples++;
                }

                // Dynamic Auto-Calibrating Anti-Drift:
                // If the gyroscope velocity is extremely low, adaptively adjust the offsets
                final double magnitude = sqrt(
                  event.x * event.x + event.y * event.y,
                );
                if (magnitude < 0.015) {
                  _offsetX = _offsetX * 0.995 + event.x * 0.005;
                  _offsetY = _offsetY * 0.995 + event.y * 0.005;
                }

                final adjustedX = event.x - _offsetX;
                final adjustedY = event.y - _offsetY;

                // Gravity reference for pitch channel in Landscape Left:
                // Horizon (0°): accelX ≈ +9.8, accelZ ≈ 0 -> atan2(0, 9.8) = 0.0
                // Look up (ceiling): atan2(+9.8, 0) = +1.57 rad
                // Look down (feet): atan2(-9.8, 0) = -1.57 rad
                double gravityPitch() {
                  final ax = _accelX.abs() < 0.01 ? 0.01 : _accelX;
                  return atan2(_accelZ, ax);
                }

                final now = DateTime.now();
                if (_lastTimestamp == null) {
                  _lastTimestamp = now;
                  _yawFused = 0.0;
                  _pitchFused = gravityPitch();
                  _prevYawFused = _yawFused;
                  _prevPitchFused = _pitchFused;
                  return;
                }

                final dt =
                    now.difference(_lastTimestamp!).inMicroseconds / 1000000.0;
                _lastTimestamp = now;

                // Yaw in Landscape Left: turning head LEFT produces adjustedX > 0,
                // so +adjustedX increases camera yaw (looking left).
                _yawFused += adjustedX * dt;

                // Pitch in Landscape Left: tilting head UP increases camera pitch (looking up).
                _pitchFused =
                    _alpha * (_pitchFused + adjustedY * dt) +
                    (1 - _alpha) * gravityPitch();

                final predictionTime = predictionMs / 1000.0;
                final predictedYaw = _yawFused + adjustedX * predictionTime;
                final predictedPitch = _pitchFused + adjustedY * predictionTime;

                final dYaw = predictedYaw - (_prevYawFused ?? predictedYaw);
                final dPitch =
                    predictedPitch - (_prevPitchFused ?? predictedPitch);

                _prevYawFused = predictedYaw;
                _prevPitchFused = predictedPitch;

                if (jitterDamping) {
                  // Deadband for tiny sensor vibrations
                  final rawDYaw = dYaw.abs() < 0.00015 ? 0.0 : dYaw;
                  final rawDPitch = dPitch.abs() < 0.00015 ? 0.0 : dPitch;
                  // Fast exponential filter
                  _dampedDYaw = _dampedDYaw * 0.15 + rawDYaw * 0.85;
                  _dampedDPitch = _dampedDPitch * 0.15 + rawDPitch * 0.85;
                  target.rotate(_dampedDYaw * sensitivity, _dampedDPitch * sensitivity * pitchGain);
                } else {
                  target.rotate(dYaw * sensitivity, dPitch * sensitivity * pitchGain);
                }
              });
      return;
    }

    // Native Platform: Background Isolate Setup
    final fusionIsolate = BackgroundIsolate.create();
    _fusionIsolate = fusionIsolate;

    fusionIsolate.messages.listen((message) {
      if (message is List) {
        final dYaw = (message[0] as num).toDouble();
        final dPitch = (message[1] as num).toDouble();
        target.rotate(dYaw, dPitch);
      } else {
        // First message: the worker's SendPort (two-way channel)
        _isolateSendPort = message;
        _isolateSendPort.send([
          0,
          _alpha,
          sensitivity,
          predictionMs,
          _offsetX,
          _offsetY,
        ]);
      }
    });

    fusionIsolate.start(headTrackingFusionEntry);

    _accelSubscription =
        (accelerometerStreamOverride ??
                accelerometerEventStream(
                  samplingPeriod: SensorInterval.fastestInterval,
                ))
            .listen((event) {
              _isolateSendPort?.send([1, event.x, event.y, event.z]);

              if (!isGyroscopeActive) {
                _updateFromAccelerometerOnly(event.x, event.y, event.z);
              }
            });

    _subscription =
        (gyroscopeStreamOverride ??
                gyroscopeEventStream(
                  samplingPeriod: SensorInterval.fastestInterval,
                ))
            .listen((event) {
              _gyroEventsCount++;
              isGyroscopeActive = true;

              if (_calibrating) {
                _calibrationSumX += event.x;
                _calibrationSumY += event.y;
                _calibrationSamples++;
              }
              _isolateSendPort?.send([2, event.x, event.y, event.z]);
            });
  }

  /// Estimates pitch (tilt up/down) directly from gravity when no gyroscope is available.
  void _updateFromAccelerometerOnly(double ax, double ay, double az) {
    final axSafe = ax.abs() < 0.01 ? 0.01 : ax;
    final double pitch = atan2(az, axSafe);

    // Low-pass filter to smooth hand jitters
    _smoothPitch = _smoothPitch * 0.85 + pitch * 0.15;

    if (_lastAccelPitch != null) {
      final dPitch = _smoothPitch - _lastAccelPitch!;
      // Apply pitch (vertical look) delta to camera.
      target.rotate(0.0, dPitch * sensitivity * pitchGain);
    }

    _lastAccelPitch = _smoothPitch;
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
        // Update background isolate config
        _isolateSendPort?.send([
          0,
          _alpha,
          sensitivity,
          predictionMs,
          _offsetX,
          _offsetY,
        ]);
      }
      _calibrating = false;
    });
  }

  /// Recenters the horizontal head-tracking azimuth (Yaw = 0°).
  void recenter() {
    _yawFused = 0.0;
    _prevYawFused = null;
    target.recenter();
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

    _fusionIsolate?.dispose();
    _fusionIsolate = null;
    _isolateSendPort = null;
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

  @override
  void recenter() {
    try {
      _target.recenter();
    } catch (_) {
      _target.reset();
    }
  }
}

/// Driver that feeds live camera/MLKit 3D face position coordinates into [CameraRig].
/// Delivers the Looking-Glass "Holographic 3D Window" effect by altering off-axis projection.
class FaceTrackerDriver {
  final dynamic cameraRig;

  Vector3 facePosition = Vector3(0, 0, 0.4); // Default 40cm in front of screen

  FaceTrackerDriver({required this.cameraRig});

  /// Feeds new 3D eye/face coordinates from camera landmark stream (in meters relative to screen center).
  void updateFacePosition(double x, double y, double distanceMeters) {
    facePosition = Vector3(x, y, distanceMeters);
  }

  /// Calculates the current face-tracked holographic projection matrix for the rig.
  Matrix4 get projectionMatrix {
    return cameraRig.faceTrackedProjectionMatrix(eyePosRelative: facePosition);
  }
}
