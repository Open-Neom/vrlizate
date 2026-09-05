import 'dart:math' as math;

import '../vr_input_arbiter.dart';
import '../vr_input_event_bus.dart';

/// Converts normalized coordinates from a remote phone into navigation input.
///
/// The payload map is reused. Consumers must copy any values they need after
/// synchronous event dispatch.
class VrRemoteTouchpadDriver
    implements VrInputDriver, VrInputPrioritizedDriver {
  static const String normalizedXKey = 'touchX';
  static const String normalizedYKey = 'touchY';
  static const String axisXKey = 'x';
  static const String axisYKey = 'y';

  final double deadZone;
  late final Map<String, dynamic> _payload;

  VrInputSink? _sink;
  bool _active = false;
  double _axisX = 0;
  double _axisY = 0;

  VrRemoteTouchpadDriver({this.deadZone = 0.12}) {
    if (!deadZone.isFinite || deadZone < 0 || deadZone >= 1) {
      throw RangeError.range(
        deadZone,
        0,
        1,
        'deadZone',
        'Must be finite and in the range [0, 1).',
      );
    }
    _payload = <String, dynamic>{
      normalizedXKey: 0.5,
      normalizedYKey: 0.5,
      axisXKey: 0.0,
      axisYKey: 0.0,
    };
  }

  @override
  VrInputSource get source => VrInputSource.remotePhone;

  @override
  VrInputPriority get priority => VrInputPriority.maximum;

  bool get isAttached => _sink != null;
  bool get isActive => _active;
  double get axisX => _axisX;
  double get axisY => _axisY;

  @override
  void attach(VrInputSink sink) {
    if (_sink != null) {
      throw StateError('VrRemoteTouchpadDriver is already attached.');
    }
    _sink = sink;
  }

  @override
  void detach() {
    _sink = null;
    _active = false;
    _axisX = 0;
    _axisY = 0;
  }

  /// Emits joystick-style navigation from normalized coordinates in [0, 1].
  ///
  /// Passing two null values releases navigation. Supplying only one value is
  /// rejected because it represents an incomplete transport frame.
  bool updateTouch(double? x, double? y) {
    if (x == null || y == null) {
      if (x != null || y != null) {
        throw ArgumentError('Touch x and y must both be null or both be set.');
      }
      return _release();
    }
    if (!x.isFinite || x < 0 || x > 1 || !y.isFinite || y < 0 || y > 1) {
      throw RangeError('Touch coordinates must be finite and between 0 and 1.');
    }

    var axisX = x * 2 - 1;
    var axisY = 1 - y * 2;
    final magnitude = math.sqrt(axisX * axisX + axisY * axisY);
    if (magnitude <= deadZone) {
      axisX = 0;
      axisY = 0;
    } else if (magnitude > 0) {
      final clampedMagnitude = math.min(1.0, magnitude);
      final adjustedMagnitude = (clampedMagnitude - deadZone) / (1 - deadZone);
      final scale = adjustedMagnitude / magnitude;
      axisX *= scale;
      axisY *= scale;
    }

    _active = true;
    _axisX = axisX;
    _axisY = axisY;
    _payload[normalizedXKey] = x;
    _payload[normalizedYKey] = y;
    _payload[axisXKey] = axisX;
    _payload[axisYKey] = axisY;

    final sink = _sink;
    if (sink == null) return false;
    return sink.emit(type: VrInputType.navigate, data: _payload, active: true);
  }

  bool _release() {
    if (!_active) return false;
    _active = false;
    _axisX = 0;
    _axisY = 0;
    _payload[axisXKey] = 0.0;
    _payload[axisYKey] = 0.0;

    final sink = _sink;
    if (sink == null) return false;
    return sink.emit(type: VrInputType.navigate, data: _payload, active: false);
  }
}
