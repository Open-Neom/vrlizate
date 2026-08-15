import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart';

import '../../core/camera/camera_rig.dart';

/// Detects walking-in-place steps from the device accelerometer using
/// head-bob analysis (VR-Step style).
///
/// With the phone mounted in a Cardboard-class viewer, walking or jogging in
/// place produces a quasi-sinusoidal vertical acceleration of the head. This
/// detector estimates gravity with a low-pass filter, projects the dynamic
/// acceleration onto the gravity axis, and applies peak detection with a
/// refractory period to count individual steps.
///
/// Works with any device orientation because the gravity vector is estimated
/// at runtime rather than assuming a fixed axis.
class WalkInPlaceDetector {
  /// Minimum dynamic vertical acceleration (m/s²) to consider a step peak.
  double stepThreshold;

  /// Minimum time between two consecutive steps.
  Duration refractoryPeriod;

  /// Low-pass factor for gravity estimation (0..1, higher = slower adapt).
  double gravitySmoothing;

  StreamSubscription<AccelerometerEvent>? _subscription;
  final Stream<AccelerometerEvent>? accelerometerStreamOverride;

  /// Called each time a step is detected.
  void Function()? onStep;

  /// Called with the updated cadence (steps per minute) after each step.
  void Function(double stepsPerMinute)? onCadenceChanged;

  /// Whether the detector is currently listening to the accelerometer.
  bool get isActive => _subscription != null;

  // Gravity estimation state.
  Vector3? _gravity;

  // Dynamic vertical signal state (high-pass along gravity axis).
  double _prevSignal = 0;
  bool _rising = false;
  double _peakCandidate = 0;
  DateTime? _lastStepTime;

  // Clock driven by sensor event timestamps (test-friendly).
  DateTime? _now;
  DateTime get _clock => _now ?? DateTime.now();

  // Cadence tracking: timestamps of the most recent steps.
  final Queue<DateTime> _stepTimes = Queue<DateTime>();
  static const Duration _cadenceWindow = Duration(seconds: 4);

  /// Total steps detected since [start].
  int stepCount = 0;

  /// Current cadence in steps per minute (0 when idle).
  double get cadence {
    _pruneCadenceWindow();
    if (_stepTimes.length < 2) return 0;
    final span = _stepTimes.last.difference(_stepTimes.first).inMilliseconds;
    if (span <= 0) return 0;
    return (_stepTimes.length - 1) * 60000.0 / span;
  }

  WalkInPlaceDetector({
    this.stepThreshold = 1.2,
    this.refractoryPeriod = const Duration(milliseconds: 280),
    this.gravitySmoothing = 0.96,
    this.accelerometerStreamOverride,
    this.onStep,
    this.onCadenceChanged,
  });

  /// Starts listening to the accelerometer.
  void start() {
    stop();
    reset();
    _subscription = (accelerometerStreamOverride ?? accelerometerEventStream())
        .listen(_onAccelerometer);
  }

  /// Clears all detection state without touching the sensor subscription.
  void reset() {
    stepCount = 0;
    _stepTimes.clear();
    _lastStepTime = null;
    _rising = false;
    _prevSignal = 0;
    _gravity = null;
    _now = null;
  }

  /// Feeds a raw accelerometer sample (also usable for tests).
  void feedSample(double x, double y, double z, [DateTime? timestamp]) =>
      _onAccelerometer(
        AccelerometerEvent(x, y, z, timestamp ?? DateTime.now()),
      );

  void _onAccelerometer(AccelerometerEvent event) {
    _now = event.timestamp;
    final sample = Vector3(event.x, event.y, event.z);

    // Low-pass: estimate gravity direction and magnitude.
    if (_gravity == null) {
      _gravity = sample.clone();
      return;
    }
    final g = _gravity!;
    g.setFrom(g * gravitySmoothing + sample * (1 - gravitySmoothing));

    final gMag = g.length;
    if (gMag < 1e-6) return;

    // High-pass: dynamic acceleration along the gravity (vertical) axis.
    final vertical = sample.dot(g) / gMag;
    final signal = vertical - gMag;

    _detectPeak(signal);
    _prevSignal = signal;
  }

  void _detectPeak(double signal) {
    if (signal > _prevSignal) {
      // Rising slope: track the maximum as a peak candidate.
      _rising = true;
      if (signal > _peakCandidate) _peakCandidate = signal;
      return;
    }

    // Falling slope after a rise: confirm the peak if it clears the threshold.
    if (_rising && _peakCandidate > stepThreshold) {
      final now = _clock;
      final last = _lastStepTime;
      if (last == null || now.difference(last) >= refractoryPeriod) {
        _lastStepTime = now;
        stepCount++;
        _stepTimes.addLast(now);
        _pruneCadenceWindow();
        onStep?.call();
        onCadenceChanged?.call(cadence);
      }
      _rising = false;
      _peakCandidate = 0;
    }

    // Reset the candidate when the signal falls back near the baseline.
    if (signal < stepThreshold * 0.3) {
      _rising = false;
      _peakCandidate = 0;
    }
  }

  void _pruneCadenceWindow() {
    final cutoff = _clock.subtract(_cadenceWindow);
    while (_stepTimes.isNotEmpty && _stepTimes.first.isBefore(cutoff)) {
      _stepTimes.removeFirst();
    }
  }

  /// Stops listening to the accelerometer.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
  }
}

/// Walk-in-place locomotion: converts detected steps into forward movement
/// of the camera rig, in the head's ground-projected forward direction.
///
/// Movement speed scales with step cadence and decays smoothly when the user
/// stops stepping, avoiding abrupt stops that cause vection discomfort.
class WalkInPlaceLocomotion {
  final CameraRig cameraRig;
  final WalkInPlaceDetector detector;

  /// Speed in units per second at [referenceCadence] steps per minute.
  double speed;

  /// Cadence (steps/min) that maps to full [speed]. Typical marching is
  /// around 110–130 spm.
  double referenceCadence;

  /// How fast (per second) the velocity decays once stepping stops.
  double deceleration;

  /// Current movement velocity in units per second (read-only).
  double get currentVelocity => _velocity;
  double _velocity = 0;

  WalkInPlaceLocomotion({
    required this.cameraRig,
    WalkInPlaceDetector? detector,
    this.speed = 1.4,
    this.referenceCadence = 120,
    this.deceleration = 4.0,
  }) : detector = detector ?? WalkInPlaceDetector();

  /// Starts step detection.
  void start() => detector.start();

  /// Stops step detection and movement.
  void stop() {
    detector.stop();
    _velocity = 0;
  }

  /// Call each frame to move the camera while steps are being detected.
  void update(double dt) {
    final cadence = detector.cadence;

    final targetVelocity = cadence > 0
        ? speed * (cadence / referenceCadence).clamp(0.0, 1.5)
        : 0.0;

    if (targetVelocity > _velocity) {
      _velocity = targetVelocity;
    } else {
      _velocity = math.max(0, _velocity - deceleration * dt);
    }

    if (_velocity <= 0) return;

    final forward = cameraRig.headTransform.forward;
    final moveForward = Vector3(forward.x, 0, forward.z);
    if (moveForward.length2 < 1e-9) return;
    moveForward.normalize();

    cameraRig.position = cameraRig.position + moveForward * (_velocity * dt);
  }

  void dispose() {
    detector.dispose();
    _velocity = 0;
  }
}
