import 'dart:ui';

import 'package:vector_math/vector_math.dart';

import '../../core/camera/camera_rig.dart';
import '../../core/input/controller_state.dart';
import '../../interaction/raycast.dart';
import '../../scene/node.dart';

/// Teleportation locomotion: point at floor, press trigger, move there.
class TeleportLocomotion {
  final CameraRig cameraRig;
  final Raycaster _raycaster = Raycaster();

  bool isAiming = false;
  Vector3? targetPosition;

  /// Maximum teleport distance.
  double maxDistance;

  /// Height of the arc visualization.
  double arcHeight;

  /// Callback when teleport completes.
  void Function(Vector3 destination)? onTeleport;

  TeleportLocomotion({
    required this.cameraRig,
    this.maxDistance = 20,
    this.arcHeight = 3,
    this.onTeleport,
  });

  /// Call when trigger is held down to show targeting arc.
  void startAiming(ControllerState controller) {
    isAiming = true;
    // Cast ray downward in an arc to find floor
    final forward = controller.forward;
    final down = Vector3(forward.x, -0.5, forward.z)..normalize();
    targetPosition = controller.position + down * 5;
  }

  /// Call when trigger is held, updates target position.
  void updateAim(ControllerState controller, Node sceneRoot) {
    if (!isAiming) return;

    final ray = Ray.originDirection(
      controller.position,
      Vector3(controller.forward.x, -0.3, controller.forward.z)..normalize(),
    );

    final hit = _raycaster.castNearest(
      ray,
      sceneRoot,
      maxDistance: maxDistance,
    );
    if (hit != null) {
      targetPosition = hit.point;
    } else {
      targetPosition = ray.at(maxDistance * 0.5);
    }
  }

  /// Call when trigger is released to execute teleport.
  void executeTeleport() {
    if (!isAiming || targetPosition == null) return;
    isAiming = false;

    // Move camera rig to target, keeping Y height
    final dest = Vector3(
      targetPosition!.x,
      cameraRig.position.y,
      targetPosition!.z,
    );
    cameraRig.position = dest;
    onTeleport?.call(dest);
    targetPosition = null;
  }

  /// Cancel without teleporting.
  void cancelAim() {
    isAiming = false;
    targetPosition = null;
  }

  /// Renders the teleport arc and target marker.
  void renderArc(Canvas canvas, Matrix4 viewProjection, Size viewport) {
    if (!isAiming || targetPosition == null) return;

    // Simple target circle indicator
    // This would be rendered in 3D space via the scene, but for simplicity
    // we just mark the intent — the actual rendering is done by VREngine
  }
}
