import 'package:vector_math/vector_math.dart';

import '../../core/camera/camera_rig.dart';
import '../../core/input/controller_state.dart';

/// Thumbstick-based walk locomotion.
class WalkLocomotion {
  final CameraRig cameraRig;

  /// Movement speed in units per second.
  double speed;

  /// Whether to use head direction for movement (true) or controller direction (false).
  bool headRelative;

  /// Dead zone for thumbstick input (prevents drift).
  double deadZone;

  WalkLocomotion({
    required this.cameraRig,
    this.speed = 3.0,
    this.headRelative = true,
    this.deadZone = 0.15,
  });

  /// Call each frame with the controller's thumbstick state.
  void update(double dt, ControllerState controller) {
    final stick = controller.thumbstick;

    // Apply dead zone
    if (stick.length < deadZone) return;

    // Get movement direction based on head or controller orientation
    final forward = headRelative
        ? cameraRig.headTransform.forward
        : controller.forward;
    final right = headRelative
        ? cameraRig.headTransform.right
        : controller.right;

    // Zero out Y to keep movement on ground plane
    final moveForward = Vector3(forward.x, 0, forward.z)..normalize();
    final moveRight = Vector3(right.x, 0, right.z)..normalize();

    final movement =
        moveForward * (-stick.y * speed * dt) +
        moveRight * (stick.x * speed * dt);

    cameraRig.position = cameraRig.position + movement;
  }
}
