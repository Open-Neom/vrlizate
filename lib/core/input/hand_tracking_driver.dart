import 'package:vector_math/vector_math.dart';

import 'controller_state.dart';
import 'hand_state.dart';

/// A single frame of 21 hand landmarks produced by an on-device ML source
/// (MediaPipe Hand Landmarker, ML Kit, or any compatible detector).
///
/// The engine is source-agnostic: the host app owns the camera and the ML
/// model (e.g. `google_mlkit_vision`, a MediaPipe Tasks platform channel,
/// or WebRTC in-browser tracking) and feeds normalized frames here.
class HandLandmarkFrame {
  /// 21 landmarks in MediaPipe order. `x`/`y` are normalized image
  /// coordinates (0..1), `z` is relative depth with the wrist as origin.
  final List<Vector3> landmarks;

  /// Which hand this frame belongs to.
  final ControllerHand hand;

  /// Detection confidence in 0..1.
  final double confidence;

  /// Capture time of the frame.
  final DateTime timestamp;

  HandLandmarkFrame({
    required this.landmarks,
    required this.hand,
    this.confidence = 1.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// One Euro filter for low-latency smoothing of jittery landmark positions.
///
/// Adapts the smoothing cutoff to the signal speed: steady hands get heavy
/// smoothing (no jitter), fast movements get light smoothing (no lag).
class OneEuroFilter {
  /// Minimum cutoff frequency (Hz). Lower = smoother when still.
  final double minCutoff;

  /// Speed coefficient. Higher = less lag during fast motion.
  final double beta;

  /// Cutoff frequency for the derivative (Hz).
  final double dCutoff;

  Vector3? _xPrev;
  Vector3? _dxPrev;
  DateTime? _tPrev;

  OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.02, this.dCutoff = 1.0});

  /// Filters [value] sampled at [timestamp].
  Vector3 filter(Vector3 value, DateTime timestamp) {
    if (_xPrev == null || _tPrev == null) {
      _xPrev = value.clone();
      _dxPrev = Vector3.zero();
      _tPrev = timestamp;
      return value;
    }

    var dt = timestamp.difference(_tPrev!).inMicroseconds / 1e6;
    if (dt <= 0) dt = 1e-3;
    _tPrev = timestamp;

    final dx = (value - _xPrev!) / dt;
    final alphaD = _alpha(dCutoff, dt);
    final dxHat = _lerp3(_dxPrev!, dx, alphaD);

    final cutoff = minCutoff + beta * dxHat.length;
    final alpha = _alpha(cutoff, dt);
    final xHat = _lerp3(_xPrev!, value, alpha);

    _xPrev = xHat;
    _dxPrev = dxHat;
    return xHat;
  }

  /// Resets the filter state (e.g. when tracking is lost and re-acquired).
  void reset() {
    _xPrev = null;
    _dxPrev = null;
    _tPrev = null;
  }

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * 3.141592653589793 * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  static Vector3 _lerp3(Vector3 a, Vector3 b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0);
}

/// Drives [HandState] instances from real camera landmark frames.
///
/// Pipeline: raw ML frame → handedness routing → metric reprojection →
/// One Euro smoothing → OpenXR [HandState] via [MediaPipeHandDriver].
class CameraHandTrackingDriver {
  /// Width of the tracked volume in meters at the reference distance.
  /// Maps normalized image x (0..1) to [-width/2, width/2].
  double volumeWidth;

  /// Height of the tracked volume in meters at the reference distance.
  double volumeHeight;

  /// Depth scale for the relative z coordinate (meters per normalized unit).
  double depthScale;

  /// Distance from the camera at which the tracking volume is anchored.
  double baseDistance;

  /// Minimum frame confidence to accept; below it the frame is dropped.
  double minConfidence;

  /// Time without frames after which a hand is reported as lost.
  Duration trackingTimeout;

  /// Tracked hand states, keyed by hand.
  final Map<ControllerHand, HandState> hands = {
    ControllerHand.left: HandState(hand: ControllerHand.left),
    ControllerHand.right: HandState(hand: ControllerHand.right),
  };

  /// Called after a hand state is updated.
  void Function(ControllerHand hand, HandState state)? onHandUpdated;

  /// Called when a hand transitions to lost (no frames within timeout).
  void Function(ControllerHand hand)? onHandLost;

  final Map<ControllerHand, List<OneEuroFilter>> _filters = {};
  final Map<ControllerHand, DateTime> _lastFrameTime = {};

  CameraHandTrackingDriver({
    this.volumeWidth = 0.45,
    this.volumeHeight = 0.35,
    this.depthScale = 0.45,
    this.baseDistance = 0.35,
    this.minConfidence = 0.5,
    this.trackingTimeout = const Duration(milliseconds: 300),
  });

  /// Feeds one frame of raw landmarks from the camera ML pipeline.
  void feedFrame(HandLandmarkFrame frame) {
    if (frame.confidence < minConfidence) return;
    if (frame.landmarks.length < 21) return;

    final hand = frame.hand;
    _lastFrameTime[hand] = frame.timestamp;

    final filters = _filters.putIfAbsent(
      hand,
      () => List.generate(21, (_) => OneEuroFilter()),
    );

    // Reproject normalized image coordinates into metric tracking space and
    // smooth each landmark independently.
    final metric = List<Vector3>.generate(21, (i) {
      final p = frame.landmarks[i];
      final projected = Vector3(
        (p.x - 0.5) * volumeWidth,
        -(p.y - 0.5) * volumeHeight,
        -(baseDistance + p.z * depthScale),
      );
      return filters[i].filter(projected, frame.timestamp);
    });

    final state = hands[hand]!;
    MediaPipeHandDriver.updateHandFromLandmarks(state, metric);
    onHandUpdated?.call(hand, state);
  }

  /// Call periodically (e.g. each frame) to mark hands as lost when the
  /// camera has not produced landmarks recently.
  void update() {
    final now = DateTime.now();
    for (final entry in hands.entries) {
      final state = entry.value;
      if (!state.tracked) continue;
      final last = _lastFrameTime[entry.key];
      if (last == null || now.difference(last) > trackingTimeout) {
        state.tracked = false;
        _filters[entry.key]?.forEach((f) => f.reset());
        onHandLost?.call(entry.key);
      }
    }
  }

  /// Resets all tracking state.
  void reset() {
    for (final state in hands.values) {
      state.tracked = false;
    }
    _filters.clear();
    _lastFrameTime.clear();
  }

  void dispose() => reset();
}

/// Semantic gestures recognized from tracked hands.
enum HandGesture {
  /// Pinch started (thumb+index together) — the VR "click".
  pinchStart,

  /// Pinch released.
  pinchEnd,

  /// Closed fist — "back" / cancel.
  fist,

  /// Open flat hand — locomotion modifier / stop.
  flatHand,

  /// Index pointing — ray-cast aiming.
  point,

  /// Thumbs up — confirm.
  thumbsUp,

  /// Victory sign — secondary action.
  victory,
}

/// A recognized gesture event emitted by [HandGestureRecognizer].
class HandGestureEvent {
  final ControllerHand hand;
  final HandGesture gesture;
  final DateTime timestamp;

  /// Pointing ray at the moment of the event (only for aim-related gestures).
  final Ray? pointingRay;

  HandGestureEvent({
    required this.hand,
    required this.gesture,
    DateTime? timestamp,
    this.pointingRay,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Converts raw [HandState] poses into debounced semantic gesture events.
///
/// A gesture must hold steady for [minHoldDuration] before it is emitted,
/// which suppresses single-frame false positives from the ML detector.
class HandGestureRecognizer {
  /// Minimum time a pose must persist before its event fires.
  Duration minHoldDuration;

  /// Called for each recognized gesture event.
  void Function(HandGestureEvent event)? onGesture;

  final Map<ControllerHand, HandGesture?> _activeGesture = {};
  final Map<ControllerHand, HandGesture?> _pendingGesture = {};
  final Map<ControllerHand, DateTime> _pendingSince = {};
  final Set<ControllerHand> _pinching = {};

  HandGestureRecognizer({
    this.minHoldDuration = const Duration(milliseconds: 80),
    this.onGesture,
  });

  /// Evaluates the current pose of [state] each tracking frame.
  void evaluate(ControllerHand hand, HandState state) {
    if (!state.tracked) {
      _endPinchIfNeeded(hand, state);
      _activeGesture[hand] = null;
      _pendingGesture[hand] = null;
      return;
    }

    // Pinch edges fire immediately (they are the primary click mechanism).
    if (state.isPinching) {
      if (!_pinching.contains(hand)) {
        _pinching.add(hand);
        onGesture?.call(
          HandGestureEvent(
            hand: hand,
            gesture: HandGesture.pinchStart,
            pointingRay: state.pointingRay,
          ),
        );
      }
    } else {
      _endPinchIfNeeded(hand, state);
    }

    // Level gestures (fist, flat hand, point, ...) are debounced.
    final detected = _detectGesture(state);
    final active = _activeGesture[hand];

    if (detected == active) {
      _pendingGesture[hand] = null;
      return;
    }

    if (_pendingGesture[hand] != detected) {
      _pendingGesture[hand] = detected;
      _pendingSince[hand] = DateTime.now();
      return;
    }

    final since = _pendingSince[hand]!;
    if (DateTime.now().difference(since) >= minHoldDuration) {
      _activeGesture[hand] = detected;
      _pendingGesture[hand] = null;
      if (detected != null) {
        onGesture?.call(
          HandGestureEvent(
            hand: hand,
            gesture: detected,
            pointingRay: state.pointingRay,
          ),
        );
      }
    }
  }

  void _endPinchIfNeeded(ControllerHand hand, HandState state) {
    if (_pinching.remove(hand)) {
      onGesture?.call(
        HandGestureEvent(hand: hand, gesture: HandGesture.pinchEnd),
      );
    }
  }

  HandGesture? _detectGesture(HandState state) {
    // Priority order matters: fist is more specific than flat hand, etc.
    if (state.isFist) return HandGesture.fist;
    if (state.isThumbsUp) return HandGesture.thumbsUp;
    if (state.isVictory) return HandGesture.victory;
    if (state.isPointing) return HandGesture.point;
    if (state.isFlatHand) return HandGesture.flatHand;
    return null;
  }

  /// Clears all debounce state.
  void reset() {
    _activeGesture.clear();
    _pendingGesture.clear();
    _pendingSince.clear();
    _pinching.clear();
  }

  void dispose() => reset();
}
