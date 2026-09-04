import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../vr_input_arbiter.dart';
import '../vr_input_event_bus.dart';

/// Reference 3DoF laser pointer for a remote or second smartphone.
///
/// The driver keeps a raw sensor orientation and applies a yaw-only recenter
/// offset. Pointer and payload objects are reused across updates; listeners
/// must copy values they need to retain after synchronous dispatch.
class VrLaserPointerDriver implements VrInputDriver, VrInputPrioritizedDriver {
  /// Payload key containing the recentered [Quaternion].
  static const String orientationKey = 'orientation';

  /// Payload key containing the recentered forward [Vector3].
  static const String forwardKey = 'forward';

  /// Payload key containing the trigger pressed state.
  static const String pressedKey = 'pressed';

  final Quaternion _rawOrientation = Quaternion.identity();
  final Quaternion _orientation = Quaternion.identity();
  final Quaternion _yawOffset = Quaternion.identity();
  final Quaternion _rotationOperator = Quaternion.identity();
  final Vector3 _forward = Vector3(0, 0, -1);
  final Vector3 _rawForward = Vector3(0, 0, -1);

  late final Map<String, dynamic> _pointerPayload;
  late final Map<String, dynamic> _triggerPayload;

  VrInputSink? _sink;
  bool _triggerPressed = false;
  double _yawOffsetRadians = 0;

  VrLaserPointerDriver() {
    _pointerPayload = <String, dynamic>{
      orientationKey: _orientation,
      forwardKey: _forward,
    };
    _triggerPayload = <String, dynamic>{pressedKey: false};
  }

  @override
  VrInputSource get source => VrInputSource.remotePhone;

  /// Laser motion is medium priority even though generic remote-phone input is
  /// maximum priority. Direct touch and remote joystick input can supersede it.
  @override
  VrInputPriority get priority => VrInputPriority.medium;

  bool get isAttached => _sink != null;
  bool get triggerPressed => _triggerPressed;

  /// Current normalized, recentered pointer orientation.
  Quaternion get orientation => _orientation;

  /// Current normalized forward direction.
  Vector3 get forward => _forward;

  /// Stored yaw correction in radians.
  double get yawOffsetRadians => _yawOffsetRadians;

  @override
  void attach(VrInputSink sink) {
    if (_sink != null) {
      throw StateError('VrLaserPointerDriver is already attached.');
    }
    _sink = sink;
  }

  @override
  void detach() {
    _sink = null;
  }

  /// Updates the raw 3DoF pose and emits a pointer movement.
  ///
  /// The input is normalized defensively. State is updated while detached, but
  /// no pooled event is acquired until a sink is attached.
  bool updateOrientation(Quaternion q) {
    final length2 = q.length2;
    if (!length2.isFinite || length2 <= 1e-12) {
      throw ArgumentError.value(q, 'q', 'Must be a finite quaternion.');
    }

    _rawOrientation.setFrom(q);
    _rawOrientation.normalize();
    _updateCorrectedPose();

    final sink = _sink;
    if (sink == null) return false;
    return sink.emit(
      type: VrInputType.pointerMove,
      data: _pointerPayload,
      active: true,
    );
  }

  /// Emits the complete press/release state of the laser trigger.
  bool setTrigger(bool pressed) {
    _triggerPressed = pressed;
    _triggerPayload[pressedKey] = pressed;

    final sink = _sink;
    if (sink == null) return false;
    return sink.emit(
      type: VrInputType.trigger,
      data: _triggerPayload,
      active: pressed,
    );
  }

  /// Makes the current horizontal heading the new forward direction.
  ///
  /// Pitch and roll are preserved. This method only stores calibration state;
  /// the next [updateOrientation] emits the calibrated pose.
  void recenter() {
    _rotateForward(_rawOrientation, _rawForward);
    final yaw = math.atan2(-_rawForward.x, -_rawForward.z);
    _yawOffsetRadians = -yaw;

    final halfAngle = _yawOffsetRadians * 0.5;
    _yawOffset.setValues(0, math.sin(halfAngle), 0, math.cos(halfAngle));
    _updateCorrectedPose();
  }

  void _updateCorrectedPose() {
    _setProduct(_orientation, _yawOffset, _rawOrientation);
    _orientation.normalize();
    _rotateForward(_orientation, _forward);
    _forward.normalize();
  }

  void _rotateForward(Quaternion q, Vector3 out) {
    // vector_math rotates as q^-1 * v * q. Conjugating the unit quaternion
    // gives the active VR convention q * v * q^-1 expected by sensor APIs.
    _rotationOperator.setValues(-q.x, -q.y, -q.z, q.w);
    out.setValues(0, 0, -1);
    _rotationOperator.rotate(out);
  }

  static void _setProduct(Quaternion out, Quaternion left, Quaternion right) {
    final lx = left.x;
    final ly = left.y;
    final lz = left.z;
    final lw = left.w;
    final rx = right.x;
    final ry = right.y;
    final rz = right.z;
    final rw = right.w;

    out.setValues(
      lw * rx + lx * rw + ly * rz - lz * ry,
      lw * ry + ly * rw + lz * rx - lx * rz,
      lw * rz + lz * rw + lx * ry - ly * rx,
      lw * rw - lx * rx - ly * ry - lz * rz,
    );
  }
}
