import 'dart:math';

import '../../utils/vr_math.dart';
import '../input/head_tracker.dart';

/// Legacy VR camera with spherical orientation (theta/phi).
/// Used by the original neom_vr particle system.
/// For new code, prefer [CameraRig] which uses Matrix4 + Quaternion.
class VRCamera implements RotationTarget {
  double theta;
  double phi;
  double fov;
  double autoRotateSpeed;

  VRCamera({
    this.theta = 0,
    this.phi = 0,
    this.fov = 1.2,
    this.autoRotateSpeed = 0,
  });

  @override
  void rotate(double dTheta, double dPhi) {
    theta += dTheta;
    phi = (phi + dPhi).clamp(-pi / 2 + 0.01, pi / 2 - 0.01);
  }

  void update(double dt) {
    if (autoRotateSpeed != 0) {
      theta += autoRotateSpeed * dt;
    }
  }

  Offset3D worldToCamera(Offset3D point) {
    return point.rotateY(-theta).rotateX(-phi);
  }

  @override
  void reset() {
    theta = 0;
    phi = 0;
  }
}
