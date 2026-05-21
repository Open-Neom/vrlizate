import 'dart:math';

import 'package:vector_math/vector_math.dart';

import '../../utils/frustum.dart';
import '../input/head_tracker.dart';
import '../math/transform3d.dart';

/// Camera rig for VR: head position + rotation, with stereo eye offsets.
/// Produces view and projection matrices for left/right eyes.
class CameraRig implements RotationTarget {
  final Transform3D headTransform;

  /// Field of view in radians (vertical).
  double fovY;

  /// Near clip plane.
  double near;

  /// Far clip plane.
  double far;

  /// Inter-pupillary distance in meters.
  double ipd;

  CameraRig({
    Transform3D? headTransform,
    this.fovY = 1.2,
    this.near = 0.01,
    this.far = 1000,
    this.ipd = 0.064,
  }) : headTransform = headTransform ?? Transform3D();

  // ─── View Matrices ──────────────────────

  /// View matrix for the left eye.
  Matrix4 get leftViewMatrix => _viewMatrix(-ipd / 2);

  /// View matrix for the right eye.
  Matrix4 get rightViewMatrix => _viewMatrix(ipd / 2);

  /// Monoscopic view matrix (center eye).
  Matrix4 get monoViewMatrix => _viewMatrix(0);

  Matrix4 _viewMatrix(double eyeOffset) {
    final pos = headTransform.position;

    // Google Cardboard Neck Model:
    // Shift eyes around the neck pivot (vertical: +0.075m, horizontal/depth: -0.080m)
    final localEye = Vector3(eyeOffset, 0.075, -0.080);
    final rotatedEye = headTransform.rotation.rotated(localEye);
    final eyePos = pos + rotatedEye - Vector3(0.0, 0.075, 0.0);

    final target = eyePos + headTransform.forward;
    final up = headTransform.up;

    return makeViewMatrix(eyePos, target, up);
  }

  // ─── Projection Matrices ──────────────────────

  /// Projection matrix for a given aspect ratio.
  Matrix4 projectionMatrix(double aspectRatio) {
    return makePerspectiveMatrix(fovY, aspectRatio, near, far);
  }

  /// Off-axis stereo projection for left eye.
  Matrix4 leftProjectionMatrix(double aspectRatio) {
    return _offAxisProjection(aspectRatio, -ipd / 2);
  }

  /// Off-axis stereo projection for right eye.
  Matrix4 rightProjectionMatrix(double aspectRatio) {
    return _offAxisProjection(aspectRatio, ipd / 2);
  }

  Matrix4 _offAxisProjection(double aspect, double eyeOffset) {
    // Off-axis frustum shift for proper stereoscopic convergence
    final top = near * tan(fovY / 2);
    final bottom = -top;
    final shift = eyeOffset * near / 1.0; // convergence at 1 meter
    final left = -aspect * top + shift;
    final right = aspect * top + shift;

    return makeFrustumMatrix(left, right, bottom, top, near, far);
  }

  // ─── Combined Matrices ──────────────────────

  Matrix4 leftViewProjection(double aspectRatio) =>
      leftProjectionMatrix(aspectRatio) * leftViewMatrix;

  Matrix4 rightViewProjection(double aspectRatio) =>
      rightProjectionMatrix(aspectRatio) * rightViewMatrix;

  Matrix4 monoViewProjection(double aspectRatio) =>
      projectionMatrix(aspectRatio) * monoViewMatrix;

  // ─── Frustum ──────────────────────

  VrFrustum frustum(double aspectRatio) =>
      VrFrustum.fromViewProjection(monoViewProjection(aspectRatio));

  // ─── Convenience ──────────────────────

  Vector3 get position => headTransform.position;
  set position(Vector3 v) => headTransform.position = v;

  Quaternion get rotation => headTransform.rotation;
  set rotation(Quaternion q) => headTransform.rotation = q;

  void lookAt(Vector3 target) => headTransform.lookAt(target);

  @override
  void rotate(double yaw, double pitch) {
    headTransform.rotateEuler(yaw, pitch, 0);
  }

  @override
  void reset() {
    headTransform.reset();
  }
}
