import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vrlizate/vrlizate.dart';

class _Target implements RotationTarget {
  double yaw = 0;
  double pitch = 0;

  @override
  void rotate(double dTheta, double dPhi) {
    yaw += dTheta;
    pitch += dPhi;
  }

  @override
  void reset() {
    yaw = 0;
    pitch = 0;
  }

  @override
  void recenter() => reset();

  @override
  void setOrientation(double yaw, double pitch) {
    this.yaw = yaw;
    this.pitch = pitch;
  }

  @override
  void setPitch(double pitch) => this.pitch = pitch;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channels = <MethodChannel>[
    MethodChannel('dev.fluttercommunity.plus/sensors/method'),
    MethodChannel('dev.fluttercommunity.plus/sensors/accelerometer'),
    MethodChannel('dev.fluttercommunity.plus/sensors/gyroscope'),
    MethodChannel('dev.fluttercommunity.plus/sensors/user_accel'),
  ];
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add('${channel.name}:${call.method}');
        return null;
      });
    }
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('backend policy preserves Android, iOS and browser implementations', () {
    for (final platform in TargetPlatform.values) {
      expect(
        VrSensorCapabilities.supportsDeviceMotionOn(platform),
        platform == TargetPlatform.android || platform == TargetPlatform.iOS,
      );
      expect(
        VrSensorCapabilities.supportsDeviceMotionOn(platform, isWeb: true),
        isTrue,
      );
    }
  });

  test('native desktop starts no sensors or timers and keeps touch usable', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      fakeAsync((async) {
        final target = _Target();
        final tracker = HeadTracker(target: target, useIsolate: true);
        final taps = InertialTapDetector();
        expect(tracker.canStart, isFalse);
        expect(taps.canStart, isFalse);
        tracker.start();
        taps.start();
        async.flushMicrotasks();
        expect(tracker.isActive, isFalse);
        expect(tracker.isGyroscopeActive, isFalse);
        expect(taps.isActive, isFalse);
        expect(async.periodicTimerCount, 0);
        expect(async.nonPeriodicTimerCount, 0);
        expect(calls, isEmpty);
        tracker.applyTouchDelta(10, 5);
        expect(target.yaw, closeTo(-0.05, 1e-10));
        expect(target.pitch, closeTo(-0.025, 1e-10));
        tracker.recenter();
        expect(target.yaw, 0);
        tracker.dispose();
        taps.dispose();
      });
    }
  });

  test('native mobile still starts all three motion sensor channels', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      calls.clear();
      fakeAsync((async) {
        final tracker = HeadTracker(target: _Target());
        final taps = InertialTapDetector();
        expect(tracker.canStart, isTrue);
        expect(taps.canStart, isTrue);
        tracker.start();
        taps.start();
        async.flushMicrotasks();
        expect(tracker.isActive, isTrue);
        expect(taps.isActive, isTrue);
        for (final method in [
          'setAccelerationSamplingPeriod',
          'setGyroscopeSamplingPeriod',
          'setUserAccelerometerSamplingPeriod',
        ]) {
          expect(calls, contains('${channels.first.name}:$method'));
        }
        for (final channel in channels.skip(1)) {
          expect(calls, contains('${channel.name}:listen'));
        }
        tracker.dispose();
        taps.dispose();
        async.flushMicrotasks();
        expect(async.periodicTimerCount, 0);
        expect(async.nonPeriodicTimerCount, 0);
      });
    }
  });

  test('desktop gyro override does not request a native accelerometer', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    fakeAsync((async) {
      final events = StreamController<GyroscopeEvent>();
      final target = _Target();
      final tracker = HeadTracker(
        target: target,
        gyroscopeStreamOverride: events.stream,
        predictionMs: 0,
        jitterDamping: false,
      );
      expect(tracker.canStart, isTrue);
      tracker.start();
      async.elapse(const Duration(seconds: 1));
      final now = DateTime(2026);
      events.add(GyroscopeEvent(1, 0, 0, now));
      events.add(
        GyroscopeEvent(1, 0, 0, now.add(const Duration(milliseconds: 20))),
      );
      async.flushMicrotasks();
      expect(tracker.isGyroscopeActive, isTrue);
      expect(target.yaw, closeTo(0.02, 1e-10));
      expect(calls, isEmpty);
      tracker.dispose();
      events.close();
      async.flushMicrotasks();
    });
  });

  test('desktop gravity override does not request a native gyroscope', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    fakeAsync((async) {
      final events = StreamController<AccelerometerEvent>();
      final target = _Target();
      final tracker = HeadTracker(
        target: target,
        accelerometerStreamOverride: events.stream,
      );
      tracker.start();
      events.add(AccelerometerEvent(4.9, 0, 8.487, DateTime(2026)));
      async.flushMicrotasks();
      expect(tracker.canStart, isTrue);
      expect(tracker.isGyroscopeActive, isFalse);
      expect(target.pitch.abs(), greaterThan(0));
      expect(calls, isEmpty);
      tracker.dispose();
      events.close();
      async.flushMicrotasks();
    });
  });

  test('desktop temple-tap override remains usable without plugin calls', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    fakeAsync((async) {
      final events = StreamController<UserAccelerometerEvent>();
      var count = 0;
      final taps = InertialTapDetector(
        accelerometerStreamOverride: events.stream,
        onSingleTap: () => count++,
      )..start();
      final now = DateTime(2026);
      events.add(UserAccelerometerEvent(0, 0, 0, now));
      events.add(
        UserAccelerometerEvent(
          1,
          0,
          0,
          now.add(const Duration(milliseconds: 20)),
        ),
      );
      async.flushMicrotasks();
      expect(taps.isActive, isTrue);
      expect(count, 1);
      expect(calls, isEmpty);
      taps.dispose();
      events.close();
      async.flushMicrotasks();
    });
  });
}
