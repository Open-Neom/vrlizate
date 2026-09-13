import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'drivers/vr_gamepad_driver.dart';
import 'vr_input_event_bus.dart';

/// Renderer-independent, borrowed-event-safe navigation and pointer state.
///
/// Normalized axes are +X right, +Y forward/up. Hosts integrate these values
/// once per render frame, not once per network packet. The host supplies its
/// actual screen-right basis, accounting for left/right-handed renderers.
/// Remote state expires on silence; gamepads send edges and stay held until
/// release. Call [reset] on route suspension, disconnect and disposal.
class VrSpatialInputState {
  final double remoteTimeoutSeconds;
  double moveX = 0;
  double moveY = 0;
  double lookX = 0;
  double lookY = 0;
  bool _moveRemote = false;
  bool _lookRemote = false;
  double _moveAge = 0;
  double _lookAge = 0;
  double _pointerAge = 0;
  bool _pointerActive = false;
  bool _pointerRemote = false;
  bool _relativePointer = false;
  VrInputSource? _moveSource;
  VrInputSource? _lookSource;
  VrInputSource? _pointerSource;
  double _laserX = 0;
  double _laserY = 0;
  final Vector3 _pointerForward = Vector3(0, 0, -1);
  final Quaternion _rotationOperator = Quaternion.identity();

  VrSpatialInputState({this.remoteTimeoutSeconds = 0.5}) {
    if (!remoteTimeoutSeconds.isFinite || remoteTimeoutSeconds <= 0) {
      throw ArgumentError.value(remoteTimeoutSeconds, 'remoteTimeoutSeconds');
    }
  }

  bool get pointerActive => _pointerActive;

  /// Copies only scalar/vector values; never retains a pooled event or map.
  void handleEvent(VrInputEvent event) {
    final data = event.data;
    final remote = event.source == VrInputSource.remotePhone;
    if (event.type == VrInputType.navigate) {
      final stick = data?['stick'];
      final rightOnly = stick == VrGamepadStick.right || stick == 'right';
      final leftOnly = stick == VrGamepadStick.left || stick == 'left';
      if (!rightOnly && (event.active || _moveSource == event.source)) {
        moveX = event.active ? _axis(data?['stickX'] ?? data?['x']) : 0;
        moveY = event.active ? _axis(data?['stickY'] ?? data?['y']) : 0;
        _moveAge = 0;
        _moveRemote = remote;
        _moveSource = event.active ? event.source : null;
      }
      if (!leftOnly && (event.active || _lookSource == event.source)) {
        lookX = event.active
            ? _axis(
                rightOnly ? (data?['x']) : (data?['lookX'] ?? data?['turn']),
              )
            : 0;
        lookY = event.active
            ? _axis(
                rightOnly ? (data?['y']) : (data?['lookY'] ?? data?['pitch']),
              )
            : 0;
        _lookAge = 0;
        _lookRemote = remote;
        _lookSource = event.active ? event.source : null;
      }
    } else if (event.type == VrInputType.pointerMove) {
      if (!event.active && _pointerSource != event.source) return;
      _pointerSource = event.active ? event.source : null;
      _pointerActive = event.active;
      _pointerRemote = remote;
      _pointerAge = 0;
      if (!event.active) return;
      _relativePointer = data?['relativeToHead'] == true;
      if (_relativePointer) {
        _laserX = _axis(data?['laserX'] ?? data?['x']);
        _laserY = _axis(data?['laserY'] ?? data?['y']);
        return;
      }
      final forward = data?['forward'];
      final orientation = data?['orientation'];
      if (forward is Vector3 && _validDirection(forward)) {
        _pointerForward.setFrom(forward);
      } else if (orientation is Quaternion &&
          orientation.length2.isFinite &&
          orientation.length2 > 1e-12) {
        // Sensor/laser drivers use active q*v*q^-1; vector_math.rotate uses
        // the inverse convention, so conjugate the normalized quaternion.
        _rotationOperator.setValues(
          -orientation.x,
          -orientation.y,
          -orientation.z,
          orientation.w,
        );
        _rotationOperator.normalize();
        _pointerForward.setValues(0, 0, -1);
        _rotationOperator.rotate(_pointerForward);
      } else {
        _pointerActive = false;
        return;
      }
      _pointerForward.normalize();
    } else if (event.type == VrInputType.recenter && event.active) {
      // Await the next calibrated pose; never retain the old ray.
      _pointerActive = false;
    }
  }

  static double _axis(dynamic value) =>
      value is num && value.isFinite ? value.toDouble().clamp(-1.0, 1.0) : 0;

  static bool _validDirection(Vector3 value) =>
      value.length2.isFinite && value.length2 > 1e-12;

  void update(double dt) {
    if (!dt.isFinite || dt < 0) return;
    _moveAge += dt;
    _lookAge += dt;
    _pointerAge += dt;
    if (_moveRemote && _moveAge >= remoteTimeoutSeconds) {
      moveX = moveY = 0;
    }
    if (_lookRemote && _lookAge >= remoteTimeoutSeconds) {
      lookX = lookY = 0;
    }
    if (_pointerRemote && _pointerAge >= remoteTimeoutSeconds) {
      _pointerActive = false;
    }
  }

  /// Writes an XZ-plane displacement, with no diagonal/pitch speed boost.
  void writeMovement(
    Vector3 out, {
    required Vector3 forward,
    required Vector3 screenRight,
    required double dt,
    double speed = 3.0,
  }) {
    out.setZero();
    if (!dt.isFinite || dt <= 0 || !speed.isFinite || speed < 0) return;
    final forwardLength = math.sqrt(
      forward.x * forward.x + forward.z * forward.z,
    );
    final rightLength = math.sqrt(
      screenRight.x * screenRight.x + screenRight.z * screenRight.z,
    );
    if (forwardLength <= 1e-9 || rightLength <= 1e-9) return;
    final magnitude = math.max(1.0, math.sqrt(moveX * moveX + moveY * moveY));
    final distance = speed * dt / magnitude;
    out.setValues(
      (screenRight.x / rightLength * moveX +
              forward.x / forwardLength * moveY) *
          distance,
      0,
      (screenRight.z / rightLength * moveX +
              forward.z / forwardLength * moveY) *
          distance,
    );
  }

  /// Writes the active controller ray, falling back to head gaze on release.
  /// A touch pad uses a head-relative frontal hemisphere; IMU/driver poses
  /// supply a world-space direction. The origin is a 3DoF estimate, not 6DoF.
  void writeRay(
    Ray out, {
    required Vector3 origin,
    required Vector3 forward,
    required Vector3 screenRight,
    required Vector3 up,
  }) {
    out.origin.setFrom(origin);
    if (!_pointerActive) {
      out.direction.setFrom(forward);
    } else if (!_relativePointer) {
      out.direction.setFrom(_pointerForward);
    } else {
      final yaw = _laserX * math.pi / 2;
      final pitch = _laserY * 1.25;
      final f = math.cos(yaw) * math.cos(pitch);
      final r = math.sin(yaw) * math.cos(pitch);
      final u = math.sin(pitch);
      out.direction.setValues(
        forward.x * f + screenRight.x * r + up.x * u,
        forward.y * f + screenRight.y * r + up.y * u,
        forward.z * f + screenRight.z * r + up.z * u,
      );
    }
    if (_validDirection(out.direction)) out.direction.normalize();
  }

  void reset() {
    moveX = moveY = lookX = lookY = 0;
    _moveAge = _lookAge = _pointerAge = 0;
    _moveRemote = _lookRemote = _pointerRemote = false;
    _pointerActive = false;
    _moveSource = _lookSource = _pointerSource = null;
  }
}
