import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../interop/vr_direct_native_interop.dart';

/// Direct FFI / host bridge to iOS/macOS `CMDeviceMotion.rotationRate`, whose
/// bias is removed by Core Motion. It carries device axes in rad/s, not
/// absolute yaw.
///
/// On Apple platforms with `CoreMotion` hardware, [VrDirectCoreMotion] reads
/// `CMMotionManager` directly via Objective-C FFI (`< 1 µs`, zero Swift host
/// plugin required) whenever no custom host channel is registered. Other
/// platforms fall back to `sensors_plus`. A registered but unavailable, failing
/// or malformed channel backend never silently switches back to raw data.
class VrCoreMotionGyroscope {
  VrCoreMotionGyroscope({
    MethodChannel availabilityChannel = const MethodChannel(
      'vrlizate/head_motion',
    ),
    EventChannel eventChannel = const EventChannel(
      'vrlizate/head_motion/gyroscope',
    ),
    Stream<GyroscopeEvent> Function()? fallback,
    this.samplingPeriod = const Duration(milliseconds: 10),
  }) : _availabilityChannel = availabilityChannel,
       _eventChannel = eventChannel,
       _fallback = fallback ?? (() => _defaultFallback(samplingPeriod));

  static final shared = VrCoreMotionGyroscope();

  static Stream<GyroscopeEvent> _defaultFallback(Duration period) {
    final direct = VrDirectCoreMotion.shared;
    if (direct.isDeviceMotionAvailable) {
      return _directCoreMotionStream(direct, period);
    }
    return gyroscopeEventStream(samplingPeriod: SensorInterval.fastestInterval);
  }

  static Stream<GyroscopeEvent> _directCoreMotionStream(
    VrDirectCoreMotion direct,
    Duration period,
  ) {
    late final StreamController<GyroscopeEvent> controller;
    Timer? pollTimer;
    int? lastMicros;
    controller = StreamController<GyroscopeEvent>(
      onListen: () {
        final ok = direct.startUpdates(
          intervalSeconds: period.inMicroseconds / 1e6,
        );
        if (!ok) {
          controller.addError(
            PlatformException(code: 'head_motion_unavailable'),
          );
          return;
        }
        pollTimer = Timer.periodic(period, (_) {
          final sample = direct.readSampleSync();
          if (sample == null) return;
          if (!sample.rx.isFinite ||
              !sample.ry.isFinite ||
              !sample.rz.isFinite ||
              sample.rx.abs() > 100 ||
              sample.ry.abs() > 100 ||
              sample.rz.abs() > 100 ||
              sample.timestampMicros <= 0) {
            return;
          }
          if (lastMicros != null && sample.timestampMicros <= lastMicros!) {
            return;
          }
          lastMicros = sample.timestampMicros;
          controller.add(
            GyroscopeEvent(
              sample.rx,
              sample.ry,
              sample.rz,
              DateTime.fromMicrosecondsSinceEpoch(sample.timestampMicros),
            ),
          );
        });
      },
      onCancel: () {
        pollTimer?.cancel();
        pollTimer = null;
        direct.stopUpdates();
      },
    );
    return controller.stream;
  }

  /// Synchronous zero-serialization render-tick read from Apple `CoreMotion`
  /// when active (`< 1 µs`), avoiding async stream / message-loop latency.
  VrDirectMotionSample? readDirectSampleSync() =>
      VrDirectCoreMotion.shared.readSampleSync();

  final MethodChannel _availabilityChannel;
  final EventChannel _eventChannel;
  final Stream<GyroscopeEvent> Function() _fallback;
  final Duration samplingPeriod;
  late final _controller = StreamController<GyroscopeEvent>.broadcast(
    onListen: _start,
    onCancel: _stop,
  );
  StreamSubscription<dynamic>? _subscription;
  Future<void> _stopping = Future<void>.value();
  Completer<Object?>? _availabilityRequest;
  Timer? _availabilityTimer;
  int _generation = 0;
  int? _lastTimestampUs;
  bool _disposed = false;

  /// Shared across simultaneous trackers: one native stream starts with the
  /// first listener and stops when the last cancels. Restart waits for cancel.
  Stream<GyroscopeEvent> get stream => _controller.stream;

  bool _current(int generation) =>
      !_disposed && generation == _generation && _controller.hasListener;

  Future<void> _start() async {
    final generation = ++_generation;
    _lastTimestampUs = null;
    await _stopping;
    if (!_current(generation)) return;
    var absent = false;
    try {
      final available = await _availability();
      if (!_current(generation)) return;
      if (available is! bool) {
        throw const FormatException('Invalid head-motion availability');
      }
      if (!available) {
        throw PlatformException(code: 'head_motion_unavailable');
      }
    } on MissingPluginException {
      absent = true;
    } catch (error, stack) {
      if (_current(generation)) _controller.addError(error, stack);
      return;
    }
    if (!_current(generation)) return;
    try {
      final source = absent
          ? _fallback()
          : _eventChannel.receiveBroadcastStream({
              'samplingPeriodUs': samplingPeriod.inMicroseconds,
            });
      _subscription = source.listen(
        (dynamic value) {
          if (!_current(generation)) return;
          final event = absent
              ? (value is GyroscopeEvent ? value : null)
              : _decode(value);
          if (event == null) return;
          final timestamp = event.timestamp.microsecondsSinceEpoch;
          if (_lastTimestampUs != null && timestamp <= _lastTimestampUs!) {
            return;
          }
          _lastTimestampUs = timestamp;
          _controller.add(event);
        },
        onError: (Object error, StackTrace stack) {
          if (_current(generation)) _controller.addError(error, stack);
        },
        onDone: () {
          if (_current(generation)) {
            _controller.addError(StateError('Head-motion stream ended'));
          }
        },
      );
    } catch (error, stack) {
      if (_current(generation)) _controller.addError(error, stack);
    }
  }

  Future<Object?> _availability() {
    final completion = Completer<Object?>();
    _availabilityRequest = completion;
    _availabilityTimer = Timer(const Duration(seconds: 2), () {
      if (!completion.isCompleted) {
        completion.completeError(TimeoutException('Head-motion availability'));
      }
    });
    _availabilityChannel
        .invokeMethod<Object?>('isAvailable')
        .then(
          (value) {
            if (!completion.isCompleted) completion.complete(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!completion.isCompleted) completion.completeError(error, stack);
          },
        );
    return completion.future.whenComplete(() {
      if (identical(_availabilityRequest, completion)) {
        _availabilityTimer?.cancel();
        _availabilityTimer = null;
        _availabilityRequest = null;
      }
    });
  }

  GyroscopeEvent? _decode(dynamic value) {
    if (value is! List || value.length != 4) return null;
    for (var i = 0; i < 4; i++) {
      if (value[i] is! num || !(value[i] as num).isFinite) return null;
    }
    final x = (value[0] as num).toDouble();
    final y = (value[1] as num).toDouble();
    final z = (value[2] as num).toDouble();
    final timestamp = value[3] as num;
    // Far above a consumer gyro's normal range, while excluding corrupt data.
    if (x.abs() > 100 ||
        y.abs() > 100 ||
        z.abs() > 100 ||
        timestamp <= 0 ||
        timestamp > 8640000000000000000 ||
        timestamp != timestamp.toInt()) {
      return null;
    }
    return GyroscopeEvent(
      x,
      y,
      z,
      DateTime.fromMicrosecondsSinceEpoch(timestamp.toInt()),
    );
  }

  void _stop() {
    _generation++;
    _lastTimestampUs = null;
    _availabilityTimer?.cancel();
    _availabilityTimer = null;
    final availability = _availabilityRequest;
    _availabilityRequest = null;
    if (availability != null && !availability.isCompleted) {
      availability.completeError(StateError('Head-motion request cancelled'));
    }
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      // No retries: stop owns this subscription only, never another plugin's
      // motion manager. A late availability response cannot start a new stream.
      _stopping = subscription.cancel().catchError((Object _) {});
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stop();
    await _stopping;
    await _controller.close();
  }
}
