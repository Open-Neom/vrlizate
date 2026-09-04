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

  /// Minimum recommended IPD in meters (50mm).
  static const double minIpd = 0.050;

  /// Default adult IPD in meters (64mm).
  static const double defaultIpd = 0.064;

  /// Maximum recommended IPD in meters (80mm).
  static const double maxIpd = 0.080;

  /// Minimum recommended distance for UI/interactive elements (1.2m) to prevent VAC eye strain.
  static const double comfortDistanceMin = 1.2;

  /// Default focal distance for spatial UI (1.8m).
  static const double comfortDistanceDefault = 1.8;

  /// Maximum recommended distance for readable spatial UI (3.0m).
  static const double comfortDistanceMax = 3.0;

  double _ipd;

  /// Inter-pupillary distance in meters (clamped between 50mm and 80mm).
  ///
  /// Zero is accepted explicitly for monoscopic rendering and diagnostics.
  double get ipd => _ipd;
  set ipd(double value) => _ipd = _normalizeIpd(value);

  double _yaw = 0.0;
  double _pitch = 0.0;

  /// Horizontal azimuth angle (radians).
  double get yaw => _yaw;

  /// Vertical elevation angle (radians).
  double get pitch => _pitch;

  CameraRig({
    Transform3D? headTransform,
    this.fovY = 1.2,
    this.near = 0.01,
    this.far = 1000,
    double ipd = defaultIpd,
  }) : _ipd = _normalizeIpd(ipd),
       headTransform = headTransform ?? Transform3D() {
    _extractYawPitchFromTransform();
  }

  static double _normalizeIpd(double value) {
    if (value == 0) return 0;
    return value.clamp(minIpd, maxIpd);
  }

  void _extractYawPitchFromTransform() {
    final f = headTransform.forward;
    final horizontalDist = sqrt(f.x * f.x + f.z * f.z);
    if (horizontalDist > 0.0001) {
      _yaw = atan2(-f.x, -f.z);
    }
    _pitch = asin(f.y.clamp(-0.999, 0.999));
  }

  void _applyOrientation() {
    // Stable Horizon (0° Roll):
    // qYaw rotates around World Vertical Y-Axis (Vector3(0, 1, 0)) -> ground plane is always level!
    // qPitch rotates around Camera Local Horizontal X-Axis -> elevation clamped to prevent flipping.
    final qYaw = Quaternion.axisAngle(Vector3(0, 1, 0), _yaw);
    final qPitch = Quaternion.axisAngle(Vector3(1, 0, 0), _pitch);
    headTransform.rotation = (qYaw * qPitch)..normalize();
  }

  /// Sets the absolute gaze angles in radians.
  void setOrientation(double yaw, double pitch) {
    _yaw = yaw;
    _pitch = pitch.clamp(-1.45, 1.45); // Clamped to ±83°
    _applyOrientation();
  }

  /// Recenters horizontal gaze heading (Yaw = 0°) while maintaining pitch (elevation).
  @override
  void recenter() {
    _yaw = 0.0;
    _applyOrientation();
  }

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
  set rotation(Quaternion q) {
    headTransform.rotation = q;
    _extractYawPitchFromTransform();
  }

  void lookAt(Vector3 target) {
    final dir = (target - position).normalized();
    final horizontalDist = sqrt(dir.x * dir.x + dir.z * dir.z);
    if (horizontalDist > 0.0001) {
      _yaw = atan2(-dir.x, -dir.z);
    }
    _pitch = asin(dir.y.clamp(-0.999, 0.999));
    _applyOrientation();
  }

  @override
  void rotate(double dYaw, double dPitch) {
    _yaw += dYaw;
    _pitch = (_pitch + dPitch).clamp(-1.45, 1.45);
    _applyOrientation();
  }

  @override
  void reset() {
    _yaw = 0.0;
    _pitch = 0.0;
    headTransform.position = Vector3.zero();
    _applyOrientation();
  }

  /// Generates a face-tracked holographic projection matrix.
  /// [eyePosRelative] represents the user's tracked eye position relative to the screen center (in meters).
  /// [screenWidth] and [screenHeight] represent the physical screen size of the phone.
  Matrix4 faceTrackedProjectionMatrix({
    required Vector3 eyePosRelative,
    double screenWidth = 0.15,
    double screenHeight = 0.08,
  }) {
    final x = eyePosRelative.x;
    final y = eyePosRelative.y;
    final z = eyePosRelative.z.clamp(0.1, 10.0); // Prevent divide by zero

    final w2 = screenWidth / 2;
    final h2 = screenHeight / 2;

    // Off-axis frustum shift calculated based on eye position
    final left = (-w2 - x) * near / z;
    final right = (w2 - x) * near / z;
    final bottom = (-h2 - y) * near / z;
    final top = (h2 - y) * near / z;

    return makeFrustumMatrix(left, right, bottom, top, near, far);
  }
}
