import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart';

import 'background_isolate.dart';
import 'head_tracking_fusion.dart';
import 'vr_sensor_capabilities.dart';

/// Interface for anything that can receive rotation input.
abstract class RotationTarget {
  void rotate(double dTheta, double dPhi);
  void reset();
  void recenter() => reset();

  /// Sets absolute gaze angles (yaw, pitch) in radians.
  void setOrientation(double yaw, double pitch) {}

  /// Sets absolute elevation (pitch) in radians.
  void setPitch(double pitch) {}
}

/// Head tracking input via device gyroscope with calibration and background Isolate.
class HeadTracker {
  final RotationTarget target;

  /// Scale for gyro yaw and gyro-only relative pitch. Gravity-referenced pitch
  /// uses [pitchGain] instead. The default applies no additional delta scaling.
  double sensitivity;

  /// Scale for gravity-referenced pitch; 1.0 preserves the measured tilt.
  double pitchGain;

  /// Latency prediction compensation in milliseconds.
  double predictionMs;

  /// Whether to use background Isolate for sensor fusion (default: false).
  /// Platforms without isolate support keep using main-thread fusion.
  final bool useIsolate;

  /// Whether gyroscope is available and active.
  bool get isActive => _subscription != null;

  /// Whether a registered platform backend or an injected sensor source can
  /// be started. This does not claim that hardware is present or sending data.
  bool get canStart =>
      VrSensorCapabilities.supportsDeviceMotion ||
      gyroscopeStreamOverride != null ||
      accelerometerStreamOverride != null;

  StreamSubscription<GyroscopeEvent>? _subscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  double _offsetX = 0;
  double _offsetY = 0;
  bool _calibrating = false;
  int _calibrationSamples = 0;
  double _calibrationSumX = 0;
  double _calibrationSumY = 0;

  final HeadTrackingFusion _fusion = HeadTrackingFusion();
  AccelerometerEvent? _lastGravityEvent;

  // DSD (Dynamic Sensor Diagnostics) fallback states
  bool isGyroscopeActive = false;
  int _silentIntervals = 0;
  int _gravitySilentIntervals = 0;
  double _smoothPitch = 0.0;
  bool _running = false;
  int _session = 0;
  int _workerRevision = 0;
  Timer? _calibrationTimer;
  Timer? _healthTimer;

  BackgroundIsolate? _fusionIsolate;
  // The worker's SendPort (typed dynamically to stay WASM-compatible).
  dynamic _isolateSendPort;
  StreamSubscription<dynamic>? _workerSubscription;

  /// Whether high-frequency sensor jitter damping is active.
  bool jitterDamping;

  final Stream<GyroscopeEvent>? gyroscopeStreamOverride;
  final Stream<AccelerometerEvent>? accelerometerStreamOverride;

  HeadTracker({
    required this.target,
    this.sensitivity = 1.0,
    this.pitchGain = 1.0,
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

  /// Starts tracking. Keep the device still during the one-second calibration.
  void start() {
    stop();
    if (!canStart) return;
    _running = true;
    final session = _session;
    _offsetX = 0;
    _offsetY = 0;
    _fusion.reset(clearGravity: true);
    _lastGravityEvent = null;
    _silentIntervals = 0;
    _gravitySilentIntervals = 0;
    _smoothPitch = 0;
    calibrate();

    // One timer, not a newly allocated timer per 60–120 Hz sample.
    _healthTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_running || session != _session) return;
      if (++_silentIntervals >= 4 && isGyroscopeActive) {
        _loseGyroscope();
      }
      if (++_gravitySilentIntervals >= 4 && _lastGravityEvent != null) {
        _loseGravity();
      }
    });

    if (useIsolate) _startWorker(session);
    // An injected stream may work on desktop even though the native backend
    // does not. In that case never fill a missing channel with a plugin call.
    final platformSensors = VrSensorCapabilities.supportsDeviceMotion;
    final accelerationEvents =
        accelerometerStreamOverride ??
        (platformSensors
            ? accelerometerEventStream(
                samplingPeriod: SensorInterval.fastestInterval,
              )
            : null);
    _accelSubscription = accelerationEvents?.listen(
      (event) {
        if (!_running || session != _session) return;
        if (!_fusion.updateGravity(event.x, event.y, event.z)) return;
        _lastGravityEvent = event;
        _gravitySilentIntervals = 0;
        _isolateSendPort?.send([1, event.x, event.y, event.z]);
        if (!isGyroscopeActive) {
          _smoothPitch = _smoothPitch * 0.85 + _fusion.gravityPitch! * 0.15;
          target.setPitch(_smoothPitch * pitchGain);
        }
      },
      onError: (Object error) {
        if (_running && session == _session) _loseGravity();
      },
      onDone: () {
        if (_running && session == _session) _loseGravity();
      },
    );

    final gyroscopeEvents =
        gyroscopeStreamOverride ??
        (platformSensors
            ? gyroscopeEventStream(
                samplingPeriod: SensorInterval.fastestInterval,
              )
            : null);
    _subscription = gyroscopeEvents?.listen(
      (event) {
        if (!_running ||
            session != _session ||
            !event.x.isFinite ||
            !event.y.isFinite ||
            !event.z.isFinite) {
          return;
        }
        _silentIntervals = 0;
        if (!isGyroscopeActive) _resetFusion();
        isGyroscopeActive = true;
        if (_calibrating) {
          _calibrationSumX += event.x;
          _calibrationSumY += event.y;
          _calibrationSamples++;
          return;
        }
        final timestampUs = event.timestamp.microsecondsSinceEpoch;
        if (_isolateSendPort != null) {
          _sendConfiguration();
          _isolateSendPort.send([
            2,
            event.x,
            event.y,
            timestampUs,
            _workerRevision,
          ]);
        } else {
          _configureFusion();
          if (_fusion.addGyroscope(event.x, event.y, timestampUs)) {
            _applyFusion(_fusion.dYaw, _fusion.dPitch, _fusion.absolutePitch);
          }
        }
      },
      onError: (Object error) {
        if (_running && session == _session) _loseGyroscope();
      },
      onDone: () {
        if (_running && session == _session) _loseGyroscope();
      },
    );
  }

  void _configureFusion() {
    _fusion
      ..sensitivity = sensitivity
      ..pitchGain = pitchGain
      ..predictionMs = predictionMs
      ..jitterDamping = jitterDamping
      ..offsetX = _offsetX
      ..offsetY = _offsetY;
  }

  void _sendConfiguration({bool force = false}) {
    if (!force &&
        _fusion.sensitivity == sensitivity &&
        _fusion.pitchGain == pitchGain &&
        _fusion.predictionMs == predictionMs &&
        _fusion.jitterDamping == jitterDamping &&
        _fusion.offsetX == _offsetX &&
        _fusion.offsetY == _offsetY) {
      return;
    }
    _configureFusion();
    _isolateSendPort?.send([
      0,
      sensitivity,
      predictionMs,
      _offsetX,
      _offsetY,
      pitchGain,
      jitterDamping,
      _workerRevision,
    ]);
  }

  void _startWorker(int session) {
    final worker = BackgroundIsolate.create();
    _fusionIsolate = worker;
    _workerSubscription = worker.messages.listen((message) {
      if (!_running || session != _session) return;
      if (message is List) {
        if (_calibrating ||
            !isGyroscopeActive ||
            message[0] != _workerRevision) {
          return;
        }
        _applyFusion(
          (message[1] as num).toDouble(),
          (message[2] as num).toDouble(),
          (message[3] as num?)?.toDouble(),
        );
      } else {
        _isolateSendPort = message;
        _sendConfiguration(force: true);
        final gravity = _lastGravityEvent;
        if (gravity != null) {
          _isolateSendPort.send([1, gravity.x, gravity.y, gravity.z]);
        }
      }
    });
    unawaited(
      worker.start(headTrackingFusionEntry).catchError((Object error) {
        if (!_running || session != _session) return;
        _workerSubscription?.cancel();
        _workerSubscription = null;
        worker.dispose();
        _fusionIsolate = null;
        _isolateSendPort = null;
        _fusion.reset();
        // Subsequent samples transparently use the same fusion on the main thread.
      }),
    );
  }

  void _applyFusion(double dYaw, double dPitch, double? pitch) {
    if (dYaw != 0 || dPitch != 0) target.rotate(dYaw, dPitch);
    if (pitch != null) target.setPitch(pitch);
  }

  void _resetFusion() {
    _fusion.reset();
    _workerRevision++;
    _isolateSendPort?.send([3, _workerRevision]);
  }

  void _loseGyroscope() {
    isGyroscopeActive = false;
    _resetFusion();
    _smoothPitch = _fusion.gravityPitch ?? 0;
  }

  void _loseGravity() {
    _lastGravityEvent = null;
    _fusion.clearGravity();
    _workerRevision++;
    _isolateSendPort?.send([4, _workerRevision]);
  }

  /// Averages gyro bias over one second while the device is stationary.
  /// Slow motion is not automatically treated as bias during normal tracking.
  void calibrate() {
    _calibrationTimer?.cancel();
    _calibrating = true;
    _calibrationSamples = 0;
    _calibrationSumX = 0;
    _calibrationSumY = 0;
    _resetFusion();
    final session = _session;
    _calibrationTimer = Timer(const Duration(seconds: 1), () {
      if (!_running || session != _session) return;
      if (_calibrationSamples > 0) {
        _offsetX = _calibrationSumX / _calibrationSamples;
        _offsetY = _calibrationSumY / _calibrationSamples;
      }
      _resetFusion();
      _configureFusion();
      _sendConfiguration(force: true);
      _calibrating = false;
    });
  }

  /// Recenters yaw without inventing pitch when no valid gravity sample exists.
  void recenter() {
    _resetFusion();
    target.recenter();
    final gravity = _fusion.gravityPitch;
    if (gravity != null) {
      _smoothPitch = gravity;
      target.setPitch(gravity * pitchGain);
    }
  }

  /// Applies touch/pan rotation when no live gyroscope is delivering samples.
  void applyTouchDelta(
    double dx,
    double dy, {
    double touchSensitivity = 0.005,
  }) {
    if (isGyroscopeActive) return;
    target.rotate(-dx * touchSensitivity, -dy * touchSensitivity);
  }

  /// Stops streams, timers, queued worker output and any pending calibration.
  void stop() {
    _running = false;
    _session++;
    _calibrationTimer?.cancel();
    _calibrationTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _calibrating = false;
    isGyroscopeActive = false;
    _subscription?.cancel();
    _subscription = null;
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _workerSubscription?.cancel();
    _workerSubscription = null;
    _fusionIsolate?.dispose();
    _fusionIsolate = null;
    _isolateSendPort = null;
    _lastGravityEvent = null;
    _fusion.reset(clearGravity: true);
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

  @override
  void setOrientation(double yaw, double pitch) {
    try {
      _target.setOrientation(yaw, pitch);
    } catch (_) {
      // ignore
    }
  }

  @override
  void setPitch(double pitch) {
    try {
      _target.setPitch(pitch);
    } catch (_) {
      // ignore
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
