import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../core/camera/camera_rig.dart';
import '../core/network/vr_controller_protocol.dart';

/// Head-relative pseudo-6DoF position model for a 3DoF phone controller.
///
/// It never claims measured translation. Instead, it starts at a comfortable
/// rest position and moves that virtual hand within a bounded envelope using
/// the controller orientation. The local offset is smoothed while head motion
/// remains immediate, avoiding the sensation that the controller lags behind
/// the user when they turn their head.
class VrControllerArmModel {
  final VrControllerHandedness handedness;
  final Vector3 restOffset;
  final double horizontalReach;
  final double verticalReach;
  final double depthReach;
  final double responsiveness;

  final Quaternion _rotationOperator = Quaternion.identity();
  final Vector3 _controllerForward = Vector3(0, 0, -1);
  final Vector3 _headForward = Vector3.zero();
  final Vector3 _headRight = Vector3.zero();
  final Vector3 _headUp = Vector3.zero();

  double _localX = 0;
  double _localY = 0;
  double _localZ = 0;
  bool _initialized = false;

  VrControllerArmModel({
    this.handedness = VrControllerHandedness.right,
    Vector3? restOffset,
    this.horizontalReach = 0.12,
    this.verticalReach = 0.10,
    this.depthReach = 0.08,
    this.responsiveness = 18,
  }) : restOffset =
           restOffset?.clone() ??
           Vector3(
             handedness == VrControllerHandedness.left ? -0.25 : 0.25,
             -0.24,
             0.55,
           ) {
    _requireNonNegative(horizontalReach, 'horizontalReach');
    _requireNonNegative(verticalReach, 'verticalReach');
    _requireNonNegative(depthReach, 'depthReach');
    if (!responsiveness.isFinite || responsiveness <= 0) {
      throw ArgumentError.value(
        responsiveness,
        'responsiveness',
        'Must be finite and positive.',
      );
    }
  }

  /// Writes the estimated world-space hand position into [out].
  void update({
    required CameraRig cameraRig,
    required Quaternion controllerOrientation,
    required double dt,
    required Vector3 out,
  }) {
    if (!dt.isFinite || dt < 0) {
      throw ArgumentError.value(dt, 'dt', 'Must be finite and non-negative.');
    }

    cameraRig.headTransform.copyForwardTo(_headForward);
    cameraRig.headTransform.copyRightTo(_headRight);
    cameraRig.headTransform.copyUpTo(_headUp);
    _rotateControllerForward(controllerOrientation);

    final horizontal = _controllerForward.dot(_headRight).clamp(-1.0, 1.0);
    final vertical = _controllerForward.dot(_headUp).clamp(-1.0, 1.0);
    final alignment = _controllerForward.dot(_headForward).clamp(-1.0, 1.0);
    final targetX = restOffset.x + horizontal * horizontalReach;
    final targetY = restOffset.y + vertical * verticalReach;
    final targetZ = restOffset.z - (1 - alignment) * 0.5 * depthReach;

    if (!_initialized || dt == 0) {
      _localX = targetX;
      _localY = targetY;
      _localZ = targetZ;
      _initialized = true;
    } else {
      final alpha = 1 - math.exp(-responsiveness * dt);
      _localX += (targetX - _localX) * alpha;
      _localY += (targetY - _localY) * alpha;
      _localZ += (targetZ - _localZ) * alpha;
    }

    final head = cameraRig.position;
    out.setValues(
      head.x +
          _headRight.x * _localX +
          _headUp.x * _localY +
          _headForward.x * _localZ,
      head.y +
          _headRight.y * _localX +
          _headUp.y * _localY +
          _headForward.y * _localZ,
      head.z +
          _headRight.z * _localX +
          _headUp.z * _localY +
          _headForward.z * _localZ,
    );
  }

  void reset() {
    _localX = 0;
    _localY = 0;
    _localZ = 0;
    _initialized = false;
  }

  void _rotateControllerForward(Quaternion orientation) {
    // Keep the same active sensor convention used by VrLaserPointerDriver.
    _rotationOperator.setValues(
      -orientation.x,
      -orientation.y,
      -orientation.z,
      orientation.w,
    );
    _controllerForward.setValues(0, 0, -1);
    _rotationOperator.rotate(_controllerForward);
    _controllerForward.normalize();
  }

  static void _requireNonNegative(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        name,
        'Must be finite and non-negative.',
      );
    }
  }
}
