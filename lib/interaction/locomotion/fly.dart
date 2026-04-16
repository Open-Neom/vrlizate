import 'package:vector_math/vector_math.dart';

import '../../core/camera/camera_rig.dart';
import '../../core/input/controller_state.dart';

/// Free-fly locomotion: move in any direction including up/down.
class FlyLocomotion {
  final CameraRig cameraRig;

  /// Movement speed in units per second.
  double speed;

  /// Vertical speed multiplier for up/down.
  double verticalSpeed;

  /// Dead zone for thumbstick input.
  double deadZone;

  FlyLocomotion({
    required this.cameraRig,
    this.speed = 5.0,
    this.verticalSpeed = 3.0,
    this.deadZone = 0.15,
  });

  /// Call each frame with primary (left) and secondary (right) controllers.
  /// Left thumbstick: horizontal movement (forward/back, strafe).
  /// Right thumbstick: vertical (up/down) + rotation.
  void update(
    double dt, {
    ControllerState? leftController,
    ControllerState? rightController,
  }) {
    // Horizontal movement from left thumbstick
    if (leftController != null) {
      final stick = leftController.thumbstick;
      if (stick.length > deadZone) {
        final forward = cameraRig.headTransform.forward;
        final right = cameraRig.headTransform.right;

        final movement =
            forward * (-stick.y * speed * dt) + right * (stick.x * speed * dt);

        cameraRig.position = cameraRig.position + movement;
      }
    }

    // Vertical + rotation from right thumbstick
    if (rightController != null) {
      final stick = rightController.thumbstick;
      if (stick.length > deadZone) {
        // Y axis: up/down
        cameraRig.position =
            cameraRig.position + Vector3(0, -stick.y * verticalSpeed * dt, 0);

        // X axis: snap turn rotation (45 degree increments)
        if (stick.x.abs() > 0.7) {
          cameraRig.rotate(stick.x > 0 ? -0.785 : 0.785, 0); // ±45°
        }
      }
    }
  }
}
