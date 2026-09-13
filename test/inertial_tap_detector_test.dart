import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vrlizate/core/input/inertial_tap_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  test(
    'timestamped 50 Hz burst detects a single tap without wall-clock delay',
    () {
      fakeAsync((async) {
        final events = StreamController<UserAccelerometerEvent>();
        var taps = 0;
        final detector = InertialTapDetector(
          accelerometerStreamOverride: events.stream,
          onSingleTap: () => taps++,
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
        expect(taps, 1);
        expect(async.nonPeriodicTimerCount, 0);
        detector.dispose();
        events.close();
      });
    },
  );

  test('double tap suppresses deferred single and bounce events', () {
    fakeAsync((async) {
      final events = StreamController<UserAccelerometerEvent>();
      var singles = 0;
      var doubles = 0;
      final detector = InertialTapDetector(
        accelerometerStreamOverride: events.stream,
        onSingleTap: () => singles++,
        onDoubleTap: () => doubles++,
      )..start();
      final now = DateTime(2026);
      void feed(int millis, double x) => events.add(
        UserAccelerometerEvent(
          x,
          0,
          0,
          now.add(Duration(milliseconds: millis)),
        ),
      );
      feed(0, 0);
      feed(20, 1);
      feed(40, 0); // Bounce inside cooldown.
      feed(300, 0); // Long gap reinitializes the derivative.
      feed(320, 1);
      async.flushMicrotasks();
      expect(doubles, 1);
      async.elapse(const Duration(seconds: 1));
      expect(singles, 0);
      detector.dispose();
      events.close();
    });
  });

  test('deferred single is cancelled by stop and restart resets tap state', () {
    fakeAsync((async) {
      final events = StreamController<UserAccelerometerEvent>.broadcast();
      var singles = 0;
      var doubles = 0;
      final detector = InertialTapDetector(
        accelerometerStreamOverride: events.stream,
        onSingleTap: () => singles++,
        onDoubleTap: () => doubles++,
      )..start();
      final now = DateTime(2026);
      void feed(int millis, double x) => events.add(
        UserAccelerometerEvent(
          x,
          0,
          0,
          now.add(Duration(milliseconds: millis)),
        ),
      );
      feed(0, 0);
      feed(20, 1);
      async.flushMicrotasks();
      detector.stop();
      async.elapse(const Duration(seconds: 1));
      expect(singles, 0);
      detector.start();
      feed(40, 0);
      feed(60, 1);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 400));
      expect(singles, 1);
      expect(doubles, 0);
      detector.dispose();
      events.close();
    });
  });

  test(
    'invalid and reordered samples cannot create taps or corrupt baseline',
    () {
      fakeAsync((async) {
        final events = StreamController<UserAccelerometerEvent>();
        var taps = 0;
        final detector = InertialTapDetector(
          accelerometerStreamOverride: events.stream,
          onSingleTap: () => taps++,
        )..start();
        final now = DateTime(2026);
        events.add(UserAccelerometerEvent(0, 0, 0, now));
        events.add(UserAccelerometerEvent(100, 0, 0, now));
        events.add(
          UserAccelerometerEvent(
            100,
            0,
            0,
            now.subtract(const Duration(milliseconds: 1)),
          ),
        );
        events.add(
          UserAccelerometerEvent(
            double.nan,
            0,
            0,
            now.add(const Duration(milliseconds: 10)),
          ),
        );
        events.add(
          UserAccelerometerEvent(
            0,
            0,
            0,
            now.add(const Duration(milliseconds: 20)),
          ),
        );
        async.flushMicrotasks();
        expect(taps, 0);
        detector.dispose();
        events.close();
      });
    },
  );
}
