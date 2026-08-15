import 'dart:async';

import 'package:vector_math/vector_math.dart';

import 'controller_state.dart';
import 'gaze_pointer.dart';
import 'hand_tracking_driver.dart';
import 'ultrasonic_gesture.dart';
import '../../interaction/locomotion/walk_in_place.dart';

/// High-level, device-agnostic VR actions produced by fusing every
/// available input channel (gaze, camera hand tracking, inertial
/// walk-in-place, and ultrasonic gestures).
sealed class VrInputAction {
  final DateTime timestamp;
  VrInputAction({DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}

/// A confirmed selection ("click") on a target, from any channel.
/// [targetId] is null when the action came from a channel without a ray
/// target (e.g. ultrasonic push with no gaze hit).
class SelectAction extends VrInputAction {
  final String? targetId;

  /// Channel that produced the selection: `gaze`, `hand`, `ultrasonic`,
  /// or `tap`.
  final String source;
  SelectAction({this.targetId, required this.source, super.timestamp});
}

/// Navigation "back" / cancel (fist gesture or ultrasonic pull).
class BackAction extends VrInputAction {
  final String source;
  BackAction({required this.source, super.timestamp});
}

/// The user is aiming with a hand ray; [ray] is the pointing ray in
/// tracking space.
class AimAction extends VrInputAction {
  final ControllerHand hand;
  final Ray ray;
  final bool active;
  AimAction({
    required this.hand,
    required this.ray,
    this.active = true,
    super.timestamp,
  });
}

/// Continuous locomotion request in units per second along the head's
/// ground-projected forward direction (0 = stop).
class MoveAction extends VrInputAction {
  final double speed;
  MoveAction({required this.speed, super.timestamp});
}

/// A confirm gesture (thumbs up / ultrasonic push while aiming).
class ConfirmAction extends VrInputAction {
  final String source;
  ConfirmAction({required this.source, super.timestamp});
}

/// Fuses the joystick-free input channels of the engine into a single
/// action stream with priority and conflict resolution:
///
/// - **Hand pinch** (camera tracking) is the primary click and overrides an
///   in-progress gaze dwell on the same frame.
/// - **Gaze dwell** is the always-available fallback click.
/// - **Ultrasonic push/pull** map to confirm/back when the camera is
///   occluded (headset cover closed, darkness).
/// - **Walk-in-place cadence** maps to continuous [MoveAction]s.
///
/// Wire the channels you have; all are optional.
class InputFusion {
  final GazePointer? gazePointer;
  final HandGestureRecognizer? gestureRecognizer;
  final WalkInPlaceDetector? walkInPlace;
  final UltrasonicGestureChannel? ultrasonic;

  /// Minimum interval between two [SelectAction]s regardless of source.
  Duration selectCooldown;

  /// Cadence (steps/min) below which no [MoveAction] is emitted.
  double minMoveCadence;

  final StreamController<VrInputAction> _actions =
      StreamController<VrInputAction>.broadcast();

  /// Unified stream of high-level VR actions.
  Stream<VrInputAction> get onAction => _actions.stream;

  DateTime? _lastSelectTime;
  bool _aiming = false;
  double _lastMoveSpeed = 0;

  InputFusion({
    this.gazePointer,
    this.gestureRecognizer,
    this.walkInPlace,
    this.ultrasonic,
    this.selectCooldown = const Duration(milliseconds: 400),
    this.minMoveCadence = 30,
  }) {
    gazePointer?.onDwellSelect = _chainGazeSelect(gazePointer!.onDwellSelect);
    gazePointer?.onTap = _chainGazeTap(gazePointer!.onTap);
    gestureRecognizer?.onGesture = _chainHandGesture(
      gestureRecognizer!.onGesture,
    );
    ultrasonic?.onGesture = _chainUltrasonic(ultrasonic!.onGesture);
  }

  void Function(String) _chainGazeSelect(void Function(String)? previous) {
    return (nodeId) {
      previous?.call(nodeId);
      _emitSelect(nodeId, 'gaze');
    };
  }

  void Function(String) _chainGazeTap(void Function(String)? previous) {
    return (nodeId) {
      previous?.call(nodeId);
      _emitSelect(nodeId, 'tap');
    };
  }

  void Function(HandGestureEvent) _chainHandGesture(
    void Function(HandGestureEvent)? previous,
  ) {
    return (event) {
      previous?.call(event);
      switch (event.gesture) {
        case HandGesture.pinchStart:
          // A deliberate pinch supersedes an in-progress dwell.
          _emitSelect(gazePointer?.gazeTargetId, 'hand');
        case HandGesture.fist:
          _actions.add(BackAction(source: 'hand'));
        case HandGesture.thumbsUp:
          _actions.add(ConfirmAction(source: 'hand'));
        case HandGesture.point:
          if (event.pointingRay != null && !_aiming) {
            _aiming = true;
            _actions.add(AimAction(hand: event.hand, ray: event.pointingRay!));
          }
        case HandGesture.flatHand:
          // Flat hand stops locomotion immediately.
          _lastMoveSpeed = 0;
          _actions.add(MoveAction(speed: 0));
        case HandGesture.pinchEnd:
        case HandGesture.victory:
          if (_aiming) {
            _aiming = false;
            final ray =
                event.pointingRay ??
                Ray.originDirection(Vector3.zero(), Vector3(0, 0, -1));
            _actions.add(AimAction(hand: event.hand, ray: ray, active: false));
          }
      }
    };
  }

  void Function(UltrasonicGestureEvent) _chainUltrasonic(
    void Function(UltrasonicGestureEvent)? previous,
  ) {
    return (event) {
      previous?.call(event);
      switch (event.gesture) {
        case UltrasonicGesture.push:
          _emitSelect(gazePointer?.gazeTargetId, 'ultrasonic');
        case UltrasonicGesture.pull:
          _actions.add(BackAction(source: 'ultrasonic'));
        case UltrasonicGesture.hoverEnter:
        case UltrasonicGesture.hoverExit:
          break; // Presence transitions are informational for now.
      }
    };
  }

  void _emitSelect(String? targetId, String source) {
    final now = DateTime.now();
    final last = _lastSelectTime;
    if (last != null && now.difference(last) < selectCooldown) return;
    _lastSelectTime = now;
    _actions.add(SelectAction(targetId: targetId, source: source));
  }

  /// Call each frame to translate walk-in-place cadence into movement.
  void update(double dt) {
    final detector = walkInPlace;
    if (detector == null) return;

    final cadence = detector.cadence;
    final speed = cadence >= minMoveCadence
        ? (cadence / 120).clamp(0.0, 1.5)
        : 0.0;

    // Emit only on meaningful change to avoid flooding the stream.
    if ((speed - _lastMoveSpeed).abs() > 0.05 ||
        (speed == 0 && _lastMoveSpeed != 0)) {
      _lastMoveSpeed = speed.toDouble();
      _actions.add(MoveAction(speed: _lastMoveSpeed));
    }
  }

  void dispose() {
    _actions.close();
  }
}
