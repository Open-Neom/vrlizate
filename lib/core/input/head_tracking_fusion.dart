import 'dart:math';

/// Shared, allocation-free fusion state for the main thread and native worker.
/// Device X drives yaw and device Y drives pitch in the existing landscape
/// mapping. Gravity is a pitch reference only; it cannot correct yaw drift.
class HeadTrackingFusion {
  double sensitivity = 1;
  double pitchGain = 1;
  double predictionMs = 15;
  bool jitterDamping = true;
  double offsetX = 0;
  double offsetY = 0;

  double? gravityPitch;
  int? _lastTimestampUs;
  double _yaw = 0;
  double _pitch = 0;
  double _previousYaw = 0;
  double _previousPitch = 0;
  double _dampedYaw = 0;
  double _dampedPitch = 0;
  bool _hasPitchReference = false;

  /// Reused output fields. [absolutePitch] is absent until gravity is valid.
  double dYaw = 0;
  double dPitch = 0;
  double? absolutePitch;

  /// Reject freefall, nonfinite data and strong linear acceleration. This is
  /// only a plausibility gate, not proof that acceleration is pure gravity.
  bool updateGravity(double x, double y, double z) {
    final magnitude2 = x * x + y * y + z * z;
    if (!magnitude2.isFinite ||
        magnitude2 < 49 ||
        magnitude2 > 156.25 ||
        x * x + z * z < 4) {
      return false;
    }
    gravityPitch = atan2(z, x).clamp(-1.45, 1.45);
    return true;
  }

  /// Continue relative gyro pitch if the accelerometer becomes unavailable.
  void clearGravity() {
    gravityPitch = null;
    _hasPitchReference = false;
    absolutePitch = null;
  }

  void reset({bool clearGravity = false}) {
    _lastTimestampUs = null;
    _yaw = 0;
    _pitch = 0;
    _previousYaw = 0;
    _previousPitch = 0;
    _dampedYaw = 0;
    _dampedPitch = 0;
    _hasPitchReference = false;
    dYaw = 0;
    dPitch = 0;
    absolutePitch = null;
    if (clearGravity) gravityPitch = null;
  }

  /// Uses acquisition time, never callback delivery time. Duplicate/out-of-
  /// order samples are ignored; gaps over 250 ms restart integration instead
  /// of extrapolating a resumed sensor across an unknown interval.
  bool addGyroscope(double x, double y, int timestampUs) {
    dYaw = 0;
    dPitch = 0;
    absolutePitch = null;
    if (!x.isFinite || !y.isFinite) return false;
    final previous = _lastTimestampUs;
    if (previous != null && timestampUs <= previous) return false;
    if (previous != null && timestampUs - previous > 250000) reset();

    if (gravityPitch != null && !_hasPitchReference) {
      _pitch = gravityPitch!;
      _previousPitch = (_pitch * pitchGain).clamp(-1.45, 1.45);
      _hasPitchReference = true;
    }
    if (_lastTimestampUs == null) {
      _lastTimestampUs = timestampUs;
      if (_hasPitchReference) {
        absolutePitch = (_pitch * pitchGain).clamp(-1.45, 1.45);
      }
      return absolutePitch != null;
    }
    final dt = (timestampUs - _lastTimestampUs!) / 1000000;
    _lastTimestampUs = timestampUs;

    // A low angular velocity is not evidence of rest. Bias changes only via
    // explicit stationary calibration, so slow intentional turns survive.
    var gx = x - offsetX;
    var gy = y - offsetY;
    if (gx.abs() < 0.002) gx = 0;
    if (gy.abs() < 0.002) gy = 0;
    _yaw += gx * dt;
    _pitch += gy * dt;
    if (_hasPitchReference) {
      // Equivalent to alpha=.98 at 100 Hz, independent of sensor frequency.
      final alpha = pow(0.98, dt * 100).toDouble();
      _pitch = alpha * _pitch + (1 - alpha) * gravityPitch!;
    }

    final prediction = predictionMs / 1000;
    final yaw = _yaw + gx * prediction;
    final pitch = ((_pitch + gy * prediction) * pitchGain).clamp(-1.45, 1.45);
    final rawYaw = yaw - _previousYaw;
    final rawPitch = pitch - _previousPitch;
    _previousYaw = yaw;
    _previousPitch = pitch;
    if (jitterDamping) {
      // Smooth without a per-frame deadband: that would erase slow motion
      // increasingly often as a device's sampling frequency increases.
      _dampedYaw = _dampedYaw * 0.15 + rawYaw * 0.85;
      _dampedPitch = _dampedPitch * 0.15 + rawPitch * 0.85;
      dYaw = _dampedYaw * sensitivity;
      dPitch = _dampedPitch * sensitivity;
    } else {
      dYaw = rawYaw * sensitivity;
      dPitch = rawPitch * sensitivity;
    }
    if (_hasPitchReference) {
      absolutePitch = pitch;
      dPitch = 0;
    }
    return true;
  }
}
