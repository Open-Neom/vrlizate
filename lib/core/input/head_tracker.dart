import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sensors_plus/sensors_plus.dart';

/// Interface for anything that can receive rotation input.
abstract class RotationTarget {
  void rotate(double dTheta, double dPhi);
  void reset();
}

/// Head tracking input via device gyroscope with calibration and background Isolate.
class HeadTracker {
  final RotationTarget target;

  /// Sensitivity multiplier for gyroscope input.
  double sensitivity;

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
  double _pitchFused = 0.0;
  double _rollFused = 0.0;
  double? _prevPitchFused;
  double? _prevRollFused;

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

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _isolateSendPort;

  final Stream<GyroscopeEvent>? gyroscopeStreamOverride;
  final Stream<AccelerometerEvent>? accelerometerStreamOverride;

  HeadTracker({
    required this.target,
    this.sensitivity = 0.03,
    this.predictionMs = 15.0,
    bool? useIsolate,
    this.gyroscopeStreamOverride,
    this.accelerometerStreamOverride,
  }) : useIsolate = useIsolate ?? (!kIsWeb);

  /// For backwards compatibility with VRCamera.
  factory HeadTracker.forCamera(
    dynamic camera, {
    double sensitivity = 0.03,
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

  /// Entry point for the background Isolate executing sensor fusion
  static void _isolateSensorFusion(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    double pitchFused = 0.0;
    double rollFused = 0.0;
    double? prevPitchFused;
    double? prevRollFused;

    double accelX = 0.0;
    double accelY = 0.0;
    double accelZ = 9.8;

    double offsetX = 0.0;
    double offsetY = 0.0;
    double alpha = 0.98;
    double sensitivity = 0.03;
    double predictionMs = 15.0;

    DateTime? lastTimestamp;

    receivePort.listen((message) {
      if (message is List) {
        final type = message[0] as int;
        if (type == 0) {
          // Configuration: [0, alpha, sensitivity, predictionMs, offsetX, offsetY]
          alpha = (message[1] as num).toDouble();
          sensitivity = (message[2] as num).toDouble();
          predictionMs = (message[3] as num).toDouble();
          offsetX = (message[4] as num).toDouble();
          offsetY = (message[5] as num).toDouble();
        } else if (type == 1) {
          // Accelerometer: [1, x, y, z]
          accelX = (message[1] as num).toDouble();
          accelY = (message[2] as num).toDouble();
          accelZ = (message[3] as num).toDouble();
        } else if (type == 2) {
          // Gyroscope: [2, x, y, z]
          final gx = (message[1] as num).toDouble();
          final gy = (message[2] as num).toDouble();

          final adjustedX = gx - offsetX;
          final adjustedY = gy - offsetY;

          final now = DateTime.now();
          if (lastTimestamp == null) {
            lastTimestamp = now;
            final accelPitch = atan2(accelY, accelZ);
            final accelRoll = atan2(
              -accelX,
              sqrt(accelY * accelY + accelZ * accelZ),
            );
            pitchFused = accelPitch;
            rollFused = accelRoll;
            prevPitchFused = accelPitch;
            prevRollFused = accelRoll;
            return;
          }

          final dt = now.difference(lastTimestamp!).inMicroseconds / 1000000.0;
          lastTimestamp = now;

          final accelPitch = atan2(accelY, accelZ);
          final accelRoll = atan2(
            -accelX,
            sqrt(accelY * accelY + accelZ * accelZ),
          );

          pitchFused =
              alpha * (pitchFused + adjustedX * dt) + (1 - alpha) * accelPitch;
          rollFused =
              alpha * (rollFused + adjustedY * dt) + (1 - alpha) * accelRoll;

          // Latency extrapolation prediction
          final predictionTime = predictionMs / 1000.0;
          final predictedPitch = pitchFused + adjustedX * predictionTime;
          final predictedRoll = rollFused + adjustedY * predictionTime;

          final dPitch = predictedPitch - (prevPitchFused ?? predictedPitch);
          final dRoll = predictedRoll - (prevRollFused ?? predictedRoll);

          prevPitchFused = predictedPitch;
          prevRollFused = predictedRoll;

          mainSendPort.send([
            -dPitch * sensitivity,
            dRoll * sensitivity * 1.8,
          ]);
        }
      }
    });
  }

  /// Starts gyroscope tracking. Calls [calibrate] automatically.
  void start() {
    stop();
    calibrate();

    _lastTimestamp = null;
    _prevPitchFused = null;
    _prevRollFused = null;
    _pitchFused = 0.0;
    _rollFused = 0.0;

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
      // Main-thread Web/Sync Fallback
      _accelSubscription =
          (accelerometerStreamOverride ?? accelerometerEventStream()).listen((
            event,
          ) {
            _accelX = event.x;
            _accelY = event.y;
            _accelZ = event.z;

            if (!isGyroscopeActive) {
              _updateFromAccelerometerOnly(event.x, event.y, event.z);
            }
          });

      _subscription = (gyroscopeStreamOverride ?? gyroscopeEventStream()).listen((
        event,
      ) {
        _gyroEventsCount++;
        isGyroscopeActive = true;

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
          final accelRoll = atan2(
            -_accelX,
            sqrt(_accelY * _accelY + _accelZ * _accelZ),
          );
          _pitchFused = accelPitch;
          _rollFused = accelRoll;
          _prevPitchFused = accelPitch;
          _prevRollFused = accelRoll;
          return;
        }

        final dt = now.difference(_lastTimestamp!).inMicroseconds / 1000000.0;
        _lastTimestamp = now;

        final accelPitch = atan2(_accelY, _accelZ);
        final accelRoll = atan2(
          -_accelX,
          sqrt(_accelY * _accelY + _accelZ * _accelZ),
        );

        _pitchFused =
            _alpha * (_pitchFused + adjustedX * dt) + (1 - _alpha) * accelPitch;
        _rollFused =
            _alpha * (_rollFused + adjustedY * dt) + (1 - _alpha) * accelRoll;

        final predictionTime = predictionMs / 1000.0;
        final predictedPitch = _pitchFused + adjustedX * predictionTime;
        final predictedRoll = _rollFused + adjustedY * predictionTime;

        final dPitch = predictedPitch - (_prevPitchFused ?? predictedPitch);
        final dRoll = predictedRoll - (_prevRollFused ?? predictedRoll);

        _prevPitchFused = predictedPitch;
        _prevRollFused = predictedRoll;

        target.rotate(-dPitch * sensitivity, dRoll * sensitivity * 1.8);
      });
      return;
    }

    // Native Platform: Background Isolate Setup
    _receivePort = ReceivePort();
    Isolate.spawn(_isolateSensorFusion, _receivePort!.sendPort).then((iso) {
      _isolate = iso;
    });

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        _isolateSendPort!.send([
          0,
          _alpha,
          sensitivity,
          predictionMs,
          _offsetX,
          _offsetY,
        ]);
      } else if (message is List) {
        final dYaw = message[0] as double;
        final dPitch = message[1] as double;
        target.rotate(dYaw, dPitch);
      }
    });

    _accelSubscription =
        (accelerometerStreamOverride ?? accelerometerEventStream()).listen((
          event,
        ) {
          _isolateSendPort?.send([1, event.x, event.y, event.z]);

          if (!isGyroscopeActive) {
            _updateFromAccelerometerOnly(event.x, event.y, event.z);
          }
        });

    _subscription = (gyroscopeStreamOverride ?? gyroscopeEventStream()).listen((
      event,
    ) {
      _gyroEventsCount++;
      isGyroscopeActive = true;

      if (_calibrating) {
        _calibrationSumX += event.x;
        _calibrationSumY += event.y;
        _calibrationSamples++;
        return;
      }
      _isolateSendPort?.send([2, event.x, event.y, event.z]);
    });
  }

  /// Estimates pitch (tilt up/down) directly from gravity when no gyroscope is available.
  void _updateFromAccelerometerOnly(double ax, double ay, double az) {
    final double pitch = atan2(ay, az);
    final double roll = atan2(-ax, sqrt(ay * ay + az * az));

    // Low-pass filter to smooth hand jitters
    _smoothPitch = _smoothPitch * 0.85 + pitch * 0.15;
    _smoothRoll = _smoothRoll * 0.85 + roll * 0.15;

    if (_lastAccelPitch != null) {
      final dPitch = _smoothPitch - _lastAccelPitch!;
      // Apply pitch (vertical look) delta to camera.
      target.rotate(0.0, dPitch * sensitivity);
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

    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
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
}
