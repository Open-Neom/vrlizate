import 'package:vector_math/vector_math.dart';

import '../math/transform3d.dart';

/// Represents the state of a VR controller (left or right hand).
class ControllerState {
  final ControllerHand hand;
  final Transform3D transform;

  bool triggerPressed;
  double triggerValue;
  bool gripPressed;
  double gripValue;
  bool primaryButtonPressed;
  bool secondaryButtonPressed;
  bool thumbstickPressed;
  Vector2 thumbstick;
  bool connected;

  ControllerState({
    required this.hand,
    Transform3D? transform,
    this.triggerPressed = false,
    this.triggerValue = 0,
    this.gripPressed = false,
    this.gripValue = 0,
    this.primaryButtonPressed = false,
    this.secondaryButtonPressed = false,
    this.thumbstickPressed = false,
    Vector2? thumbstick,
    this.connected = false,
  }) : transform = transform ?? Transform3D(),
       thumbstick = thumbstick ?? Vector2.zero();

  Vector3 get position => transform.position;
  Vector3 get forward => transform.forward;
  Vector3 get up => transform.up;
  Vector3 get right => transform.right;

  /// Ray from controller position in forward direction.
  Ray get ray => Ray.originDirection(position, forward);

  void reset() {
    triggerPressed = false;
    triggerValue = 0;
    gripPressed = false;
    gripValue = 0;
    primaryButtonPressed = false;
    secondaryButtonPressed = false;
    thumbstickPressed = false;
    thumbstick = Vector2.zero();
  }
}

enum ControllerHand { left, right }

/// A ray defined by origin and direction.
/// Named VrRay to avoid collision with vector_math's Ray.
class VrRay {
  final Vector3 origin;
  final Vector3 direction;

  const VrRay({required this.origin, required this.direction});

  /// Returns a point along the ray at distance t.
  Vector3 pointAt(double t) => origin + direction * t;
}
