import 'package:vector_math/vector_math.dart';

import '../core/camera/camera_rig.dart';
import '../scene/node.dart';

/// A node that always faces the camera (billboarding).
class Billboard extends Node {
  final CameraRig cameraRig;

  /// If true, only rotates on Y axis (cylindrical billboarding).
  final bool lockY;

  Billboard({
    super.name = 'billboard',
    required this.cameraRig,
    this.lockY = false,
  });

  @override
  void onUpdate(double dt) {
    final camPos = cameraRig.position;
    final myPos = worldPosition;

    if (lockY) {
      // Only rotate around Y axis
      final dir = Vector3(camPos.x - myPos.x, 0, camPos.z - myPos.z)
        ..normalize();
      final angle = Vector3(0, 0, -1).angleTo(dir);
      final cross = Vector3(0, 0, -1).cross(dir);
      final sign = cross.y >= 0 ? 1.0 : -1.0;
      transform.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), angle * sign);
    } else {
      // Full billboarding
      transform.lookAt(camPos);
    }
    onTransformChanged();
  }
}
