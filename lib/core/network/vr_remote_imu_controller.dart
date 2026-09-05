import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart';

import 'vr_controller_protocol.dart';
import 'vr_controller_transport.dart';

enum VrImuScreenOrientation {
  portraitUp,
  landscapeLeft,
  landscapeRight,
  portraitDown,
}

/// Child-side IMU producer for a low-cost smartphone controller.
///
/// Gyroscope samples are integrated into a recenterable 3DoF quaternion. The
/// accelerometer is transmitted for motion and diagnostics, but is deliberately
/// not integrated into position because consumer IMU translation drifts fast.
class VrRemoteImuController {
  final VrControllerTransport transport;
  final VrControllerProfile profile;
  final VrImuScreenOrientation screenOrientation;
  final Duration samplingPeriod;
  final Duration minimumSendInterval;
  final Stream<GyroscopeEvent>? gyroscopeStreamOverride;
  final Stream<AccelerometerEvent>? accelerometerStreamOverride;
  final void Function(Object error, StackTrace stackTrace)? onError;

  final Quaternion _orientation = Quaternion.identity();
  final Vector3 _angularVelocity = Vector3.zero();
  final Vector3 _accelerometer = Vector3.zero();

  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  DateTime? _lastGyroscopeTimestamp;
  int _lastSentTimestampMicroseconds = -1;
  int _sequence = 0;
  int _buttonsBitset = 0;
  double? _touchX;
  double? _touchY;
  bool _running = false;
  bool _sendInFlight = false;
  VrRemotePoseFrame? _pendingFrame;
  Completer<void>? _drainCompleter;

  VrRemoteImuController({
    required this.transport,
    required this.profile,
    this.screenOrientation = VrImuScreenOrientation.landscapeLeft,
    this.samplingPeriod = const Duration(milliseconds: 8),
    this.minimumSendInterval = const Duration(milliseconds: 16),
    this.gyroscopeStreamOverride,
    this.accelerometerStreamOverride,
    this.onError,
  }) {
    if (samplingPeriod <= Duration.zero) {
      throw ArgumentError.value(
        samplingPeriod,
        'samplingPeriod',
        'Must be positive.',
      );
    }
    if (minimumSendInterval.isNegative) {
      throw ArgumentError.value(
        minimumSendInterval,
        'minimumSendInterval',
        'Must not be negative.',
      );
    }
  }

  bool get isRunning => _running;
  Quaternion get orientation => _orientation;
  int get sequence => _sequence;
  int get buttonsBitset => _buttonsBitset;

  Future<void> start() async {
    if (_running) return;
    if (transport.state != VrTransportConnectionState.connected) {
      throw StateError(
        'Controller transport must be connected before IMU start.',
      );
    }
    await transport.sendProfile(profile);
    _running = true;
    _accelerometerSubscription =
        (accelerometerStreamOverride ??
                accelerometerEventStream(samplingPeriod: samplingPeriod))
            .listen(_onAccelerometer, onError: _handleStreamError);
    _gyroscopeSubscription =
        (gyroscopeStreamOverride ??
                gyroscopeEventStream(samplingPeriod: samplingPeriod))
            .listen(_onGyroscope, onError: _handleStreamError);
  }

  void setButtonsBitset(int value, {bool sendImmediately = true}) {
    if (value < 0) {
      throw RangeError.value(value, 'value', 'Must not be negative.');
    }
    _buttonsBitset = value;
    if (sendImmediately && _running) sendCurrentState();
  }

  void setTouch(double x, double y, {bool sendImmediately = true}) {
    if (!x.isFinite || x < 0 || x > 1 || !y.isFinite || y < 0 || y > 1) {
      throw RangeError('Touch coordinates must be finite and between 0 and 1.');
    }
    _touchX = x;
    _touchY = y;
    if (sendImmediately && _running) sendCurrentState();
  }

  void clearTouch({bool sendImmediately = true}) {
    _touchX = null;
    _touchY = null;
    if (sendImmediately && _running) sendCurrentState();
  }

  /// Resets the current physical pose to the logical controller-forward pose.
  void recenter({bool sendImmediately = true}) {
    _orientation.setValues(0, 0, 0, 1);
    _lastGyroscopeTimestamp = null;
    if (sendImmediately && _running) sendCurrentState();
  }

  void _onAccelerometer(AccelerometerEvent event) {
    _mapAxes(event.x, event.y, event.z, _accelerometer);
  }

  void _onGyroscope(GyroscopeEvent event) {
    _mapAxes(event.x, event.y, event.z, _angularVelocity);
    final previous = _lastGyroscopeTimestamp;
    _lastGyroscopeTimestamp = event.timestamp;
    if (previous != null) {
      var dt = event.timestamp.difference(previous).inMicroseconds / 1e6;
      if (dt.isFinite && dt > 0) {
        dt = dt.clamp(0.0, 0.1);
        _integrateAngularVelocity(dt);
      }
    }

    final timestampUs = event.timestamp.microsecondsSinceEpoch;
    if (_lastSentTimestampMicroseconds < 0 ||
        timestampUs - _lastSentTimestampMicroseconds >=
            minimumSendInterval.inMicroseconds) {
      _lastSentTimestampMicroseconds = timestampUs;
      _queueCurrentState(timestampUs);
    }
  }

  void sendCurrentState() =>
      _queueCurrentState(DateTime.now().microsecondsSinceEpoch);

  void _queueCurrentState(int timestampUs) {
    if (!_running) return;
    _pendingFrame = VrRemotePoseFrame(
      sequence: _sequence++,
      senderTimestampMicroseconds: timestampUs,
      orientation: _orientation,
      angularVelocity: _angularVelocity,
      accelerometer: _accelerometer,
      buttonsBitset: _buttonsBitset,
      touchX: _touchX,
      touchY: _touchY,
    );
    _pumpSendQueue();
  }

  void _pumpSendQueue() {
    if (_sendInFlight || _pendingFrame == null || !_running) return;
    final frame = _pendingFrame!;
    _pendingFrame = null;
    _sendInFlight = true;
    unawaited(
      transport
          .sendPose(frame)
          .catchError((Object error, StackTrace stackTrace) {
            onError?.call(error, stackTrace);
          })
          .whenComplete(() {
            _sendInFlight = false;
            if (_pendingFrame != null && _running) {
              _pumpSendQueue();
            } else {
              _drainCompleter?.complete();
              _drainCompleter = null;
            }
          }),
    );
  }

  void _integrateAngularVelocity(double dt) {
    final x = _angularVelocity.x;
    final y = _angularVelocity.y;
    final z = _angularVelocity.z;
    final speed = math.sqrt(x * x + y * y + z * z);
    if (speed <= 1e-8) return;
    final halfAngle = speed * dt * 0.5;
    final scale = math.sin(halfAngle) / speed;
    final dx = x * scale;
    final dy = y * scale;
    final dz = z * scale;
    final dw = math.cos(halfAngle);

    final ox = _orientation.x;
    final oy = _orientation.y;
    final oz = _orientation.z;
    final ow = _orientation.w;
    _orientation.setValues(
      ow * dx + ox * dw + oy * dz - oz * dy,
      ow * dy - ox * dz + oy * dw + oz * dx,
      ow * dz + ox * dy - oy * dx + oz * dw,
      ow * dw - ox * dx - oy * dy - oz * dz,
    );
    _orientation.normalize();
  }

  void _mapAxes(double x, double y, double z, Vector3 out) {
    switch (screenOrientation) {
      case VrImuScreenOrientation.portraitUp:
        out.setValues(x, y, z);
      case VrImuScreenOrientation.landscapeLeft:
        out.setValues(y, -x, z);
      case VrImuScreenOrientation.landscapeRight:
        out.setValues(-y, x, z);
      case VrImuScreenOrientation.portraitDown:
        out.setValues(-x, -y, z);
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    onError?.call(error, stackTrace);
  }

  Future<void> flush() {
    if (!_sendInFlight && _pendingFrame == null) return Future<void>.value();
    return (_drainCompleter ??= Completer<void>()).future;
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _gyroscopeSubscription?.cancel();
    await _accelerometerSubscription?.cancel();
    _gyroscopeSubscription = null;
    _accelerometerSubscription = null;
    _pendingFrame = null;
    await flush();
    _lastGyroscopeTimestamp = null;
  }
}
