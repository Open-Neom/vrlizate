import 'dart:math' as math;

/// One frame of assisted locomotion, expressed in the post-turn local basis.
class VrStickEdgeTurnResult {
  const VrStickEdgeTurnResult({
    this.yawDelta = 0,
    required this.movementX,
    required this.movementY,
    this.engaged = false,
  });

  /// Radians to add to the virtual body heading before applying movement.
  final double yawDelta;

  /// +X right and +Y forward, relative to the basis AFTER [yawDelta].
  final double movementX;
  final double movementY;

  /// True after the edge dwell, including when the target has been reached.
  final bool engaged;
}

/// Gradually faces the direction requested by a sustained left-stick edge.
///
/// Partial deflection remains strafing/backward movement. A full edge first
/// keeps that behavior for [holdSeconds], then accelerates a bounded virtual
/// turn. Holding the same stick direction eventually stops the turn; it does
/// not continually rotate a target relative to the newly turned body.
///
/// [update]'s heading is the virtual BODY heading, in radians positive left,
/// excluding tracked head rotation. Add the returned delta to that same body
/// heading, then use the returned axes with the updated forward/right basis.
/// This preserves the travel direction through the assisted turn without
/// counteracting physical head tracking. Physical looking remains free.
///
/// Call [reset] on route suspension, input disconnect, recenter and disposal.
/// Hosts must expire stale remote input before calling [update]. An explicit
/// right-stick look interrupts assistance until the left stick returns to
/// neutral. Games that use the left stick directly should leave this disabled.
class VrStickEdgeTurn {
  VrStickEdgeTurn({
    this.edgeThreshold = .92,
    this.releaseThreshold = .84,
    this.holdSeconds = .65,
    this.maxYawSpeed = 70 * math.pi / 180,
    this.yawAcceleration = 140 * math.pi / 180,
    this.maxStepSeconds = .05,
  }) {
    if (!edgeThreshold.isFinite ||
        !releaseThreshold.isFinite ||
        edgeThreshold > 1 ||
        edgeThreshold <= releaseThreshold ||
        releaseThreshold <= _neutralThreshold) {
      throw ArgumentError(
        'Require .15 < releaseThreshold < edgeThreshold <= 1',
      );
    }
    for (final value in [
      holdSeconds,
      maxYawSpeed,
      yawAcceleration,
      maxStepSeconds,
    ]) {
      if (!value.isFinite || value <= 0) {
        throw ArgumentError.value(
          value,
          'turn configuration',
          'Must be positive',
        );
      }
    }
  }

  final double edgeThreshold;
  final double releaseThreshold;
  final double holdSeconds;
  final double maxYawSpeed;
  final double yawAcceleration;
  final double maxStepSeconds;
  static const _neutralThreshold = .15;
  static const _oppositeBand = 7.5 * math.pi / 180;
  static const _trajectoryThreshold = 1 * math.pi / 180;
  static const _targetTolerance = .001;

  bool _edgeHeld = false;
  bool _engaged = false;
  bool _manualSuspended = false;
  double _heldSeconds = 0;
  double _targetHeading = 0;
  double _lastIntentAngle = 0;
  double? _previousMovingAngle;
  double _approachSide = 0;
  double _turnSide = -1;
  double _yawSpeed = 0;

  bool get engaged => _engaged;

  VrStickEdgeTurnResult update({
    required double stickX,
    required double stickY,
    required double heading,
    required double dt,
    double? intentX,
    double? intentY,
    bool? atEdge,
    bool enabled = true,
    bool manualLook = false,
  }) {
    // Raw intent is optional: phone controllers can send the physical thumb
    // position separately from their progressively conditioned movement axes.
    // Never infer full-edge intent from a lower movement gain.
    if (!stickX.isFinite ||
        !stickY.isFinite ||
        !heading.isFinite ||
        !dt.isFinite ||
        dt < 0 ||
        ((intentX == null) != (intentY == null)) ||
        (intentX != null && !intentX.isFinite) ||
        (intentY != null && !intentY.isFinite)) {
      reset();
      return const VrStickEdgeTurnResult(movementX: 0, movementY: 0);
    }
    final x = stickX.clamp(-1.0, 1.0);
    final y = stickY.clamp(-1.0, 1.0);
    final length = math.sqrt(x * x + y * y);
    final divisor = math.max(1.0, length);
    final movementX = x / divisor;
    final movementY = y / divisor;
    final magnitude = math.min(1.0, length);
    final rawX = (intentX ?? x).clamp(-1.0, 1.0);
    final rawY = (intentY ?? y).clamp(-1.0, 1.0);
    final rawMagnitude = math.min(1.0, math.sqrt(rawX * rawX + rawY * rawY));
    // A negotiated controller bit can retain full physical-edge intent while
    // its movement gain is still ramping. False explicitly releases the edge;
    // null preserves analog inference for older controllers and gamepads.
    final edgeMagnitude = atEdge == null
        ? rawMagnitude
        : atEdge
        ? 1.0
        : 0.0;
    final passthrough = VrStickEdgeTurnResult(
      movementX: movementX,
      movementY: movementY,
    );
    if (!enabled) {
      reset();
      return passthrough;
    }
    if (rawMagnitude <= _neutralThreshold || magnitude == 0) {
      reset();
      return passthrough;
    }
    if (manualLook) {
      reset();
      _manualSuspended = true;
      return passthrough;
    }
    if (_manualSuspended) return passthrough;

    final angle = -math.atan2(rawX, rawY);
    _recordApproach(angle, rawX);
    if (edgeMagnitude < releaseThreshold ||
        (!_engaged && edgeMagnitude < edgeThreshold)) {
      _clearEdge();
      return passthrough;
    }
    if (!_edgeHeld) {
      if (edgeMagnitude < edgeThreshold) return passthrough;
      _edgeHeld = true;
      _targetHeading = _wrap(heading + angle);
      _lastIntentAngle = angle;
      _turnSide = _approachSide != 0 ? _approachSide : -1;
    } else {
      _targetHeading = _wrap(_targetHeading + _wrap(angle - _lastIntentAngle));
      _lastIntentAngle = angle;
    }
    if (!_engaged && _approachSide != 0) _turnSide = _approachSide;

    final step = math.min(dt, maxStepSeconds);
    _heldSeconds += step;
    if (_heldSeconds + 1e-9 < holdSeconds) return passthrough;
    _engaged = true;

    var error = _wrap(_targetHeading - heading);
    // Around exactly 6 o'clock, sensor/thumb jitter across +/-pi must not
    // reverse the chosen route. The approach trajectory breaks this tie.
    if (error.abs() > math.pi - _oppositeBand) {
      error = error.abs() * _turnSide;
    } else if (error.abs() > _targetTolerance) {
      _turnSide = error.sign;
    }
    final targetSpeed = error.abs() <= _targetTolerance
        ? 0.0
        : error.sign *
              math.min(
                maxYawSpeed,
                math.sqrt(2 * yawAcceleration * error.abs()),
              );
    _yawSpeed = _approach(_yawSpeed, targetSpeed, yawAcceleration * step);
    var yawDelta = _yawSpeed * step;
    if (error.abs() <= _targetTolerance) {
      yawDelta = error.clamp(-maxYawSpeed * step, maxYawSpeed * step);
      _yawSpeed = 0;
    } else if (yawDelta.sign == error.sign && yawDelta.abs() > error.abs()) {
      yawDelta = error;
      _yawSpeed = 0;
    }

    // Remap against the post-turn body, not the original raw stick angle.
    // At the end of a backward turn the same held stick moves FORWARD in
    // the new basis, while its physical-world travel direction stays stable.
    final localDirection = _wrap(_targetHeading - heading - yawDelta);
    return VrStickEdgeTurnResult(
      yawDelta: yawDelta,
      movementX: -math.sin(localDirection) * magnitude,
      movementY: math.cos(localDirection) * magnitude,
      engaged: true,
    );
  }

  void _recordApproach(double angle, double x) {
    final previous = _previousMovingAngle;
    if (previous != null) {
      final change = _wrap(angle - previous);
      if (change.abs() >= _trajectoryThreshold &&
          change.abs() < math.pi - _oppositeBand) {
        _approachSide = change.sign;
      } else if (x.abs() >= .025 && angle.abs() < math.pi - _oppositeBand) {
        _approachSide = -x.sign;
      }
    } else if (x.abs() >= .025) {
      _approachSide = -x.sign;
    }
    _previousMovingAngle = angle;
  }

  void _clearEdge() {
    _edgeHeld = _engaged = false;
    _heldSeconds = _targetHeading = _lastIntentAngle = _yawSpeed = 0;
  }

  void reset() {
    _clearEdge();
    _manualSuspended = false;
    _previousMovingAngle = null;
    _approachSide = 0;
    _turnSide = -1;
  }

  static double _wrap(double radians) {
    final wrapped = (radians + math.pi) % (2 * math.pi) - math.pi;
    return wrapped;
  }

  static double _approach(double current, double target, double amount) =>
      current + (target - current).clamp(-amount, amount);
}
