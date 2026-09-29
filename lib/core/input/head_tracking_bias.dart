/// One-shot estimate of the small residual in an already calibrated gyro.
///
/// A request stays pending while the phone moves; it never suppresses tracking.
/// Gravity rejects tilt/translation, but cannot prove that a constant rotation
/// around vertical is rest. Consequently only a tightly bounded residual may
/// be accepted, and accepted bias is never continuously adapted during use.
class HeadTrackingBiasEstimator {
  // Below fusion's .002 rad/s noise floor: a mistaken estimate can never
  // create perpetual rotation by itself when the calibrated sensor returns 0.
  static const maxBias = .001; // rad/s, per axis, already-calibrated gyro only.
  static const minSamples = 40;
  static const minSpanUs = 800000;
  static const _maxGapUs = 250000;
  static const _maxGravityAgeUs = 200000;
  static const _maxSampleRate = .025;
  static const _maxVariance = .002 * .002;

  int? _gravityUs, _previousGyroUs, _firstUs, _lastUs;
  double _gx = 0, _gy = 0, _gz = 0;
  double _referenceGx = 0, _referenceGy = 0, _referenceGz = 0;
  double _sumX = 0, _sumY = 0, _sumZ = 0;
  double _sumXX = 0, _sumYY = 0, _sumZZ = 0;
  int _samples = 0;
  bool _accepted = false;
  double _biasX = 0, _biasY = 0;
  String _status = 'waiting_for_gravity';

  int get sampleCount => _samples;
  int get spanUs => _firstUs == null ? 0 : _lastUs! - _firstUs!;
  bool get accepted => _accepted;
  double get biasX => _biasX;
  double get biasY => _biasY;
  String get status => _status;

  void request({bool clearGravity = false}) {
    _accepted = false;
    _previousGyroUs = null;
    _resetWindow('waiting_for_stationary_samples');
    if (clearGravity) {
      _gravityUs = null;
      _status = 'waiting_for_gravity';
    }
  }

  void _resetWindow(String reason) {
    _firstUs = _lastUs = null;
    _samples = 0;
    _sumX = _sumY = _sumZ = 0;
    _sumXX = _sumYY = _sumZZ = 0;
    _status = reason;
  }

  void clearGravity() {
    _gravityUs = null;
    if (!_accepted) _resetWindow('waiting_for_gravity');
  }

  void addGravity(double x, double y, double z, int timestampUs) {
    final magnitude2 = x * x + y * y + z * z;
    if (!magnitude2.isFinite ||
        magnitude2 < 8.6 * 8.6 ||
        magnitude2 > 11 * 11) {
      _gravityUs = null;
      if (!_accepted) _resetWindow('gravity_unstable');
      return;
    }
    if (_gravityUs != null && timestampUs <= _gravityUs!) return;
    _gravityUs = timestampUs;
    _gx = x;
    _gy = y;
    _gz = z;
    if (!_accepted && _samples > 0) {
      final dx = x - _referenceGx;
      final dy = y - _referenceGy;
      final dz = z - _referenceGz;
      if (dx * dx + dy * dy + dz * dz > .25 * .25) {
        _resetWindow('gravity_moved');
      }
    }
  }

  /// Returns true exactly once per request, when a valid window is complete.
  bool addGyroscope(double x, double y, double z, int timestampUs) {
    if (_accepted) return false;
    final previous = _previousGyroUs;
    if (previous != null && timestampUs <= previous) return false;
    _previousGyroUs = timestampUs;
    if (previous != null && timestampUs - previous > _maxGapUs) {
      _resetWindow('sample_gap');
    }
    if (!x.isFinite ||
        !y.isFinite ||
        !z.isFinite ||
        x.abs() > _maxSampleRate ||
        y.abs() > _maxSampleRate ||
        z.abs() > _maxSampleRate) {
      _resetWindow('gyro_moving');
      return false;
    }
    if (_gravityUs == null ||
        (timestampUs - _gravityUs!).abs() > _maxGravityAgeUs) {
      _resetWindow('waiting_for_gravity');
      return false;
    }
    if (_firstUs == null) {
      _firstUs = timestampUs;
      _referenceGx = _gx;
      _referenceGy = _gy;
      _referenceGz = _gz;
    }
    _lastUs = timestampUs;
    _samples++;
    _sumX += x;
    _sumY += y;
    _sumZ += z;
    _sumXX += x * x;
    _sumYY += y * y;
    _sumZZ += z * z;
    _status = 'collecting';
    if (_samples < minSamples || spanUs < minSpanUs) return false;
    final meanX = _sumX / _samples;
    final meanY = _sumY / _samples;
    final meanZ = _sumZ / _samples;
    if (meanX.abs() > maxBias ||
        meanY.abs() > maxBias ||
        meanZ.abs() > maxBias) {
      _resetWindow('bias_out_of_range');
      return false;
    }
    if (_sumXX / _samples - meanX * meanX > _maxVariance ||
        _sumYY / _samples - meanY * meanY > _maxVariance ||
        _sumZZ / _samples - meanZ * meanZ > _maxVariance) {
      _resetWindow('gyro_unstable');
      return false;
    }
    _biasX = meanX;
    _biasY = meanY;
    _accepted = true;
    _status = 'accepted';
    return true;
  }
}
