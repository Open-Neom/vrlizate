import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vrlizate/vrlizate.dart';

class _Target implements RotationTarget {
  double yaw = 0;
  @override
  void rotate(double dTheta, double dPhi) => yaw += dTheta;
  @override
  void reset() => yaw = 0;
  @override
  void recenter() => reset();
  @override
  void setOrientation(double yaw, double pitch) {}
  @override
  void setPitch(double pitch) {}
}

void main() {
  tearDown(() => HeadTracker.platformGyroscopeStreamFactory = null);

  test(
    'instance override wins over host factory and stop cancels only its stream',
    () {
      fakeAsync((async) {
        var hostCalls = 0, ownCancels = 0;
        HeadTracker.platformGyroscopeStreamFactory = () {
          hostCalls++;
          return const Stream<GyroscopeEvent>.empty();
        };
        final own = StreamController<GyroscopeEvent>.broadcast(
          onCancel: () => ownCancels++,
        );
        final tracker = HeadTracker(
          target: _Target(),
          gyroscopeStreamOverride: own.stream,
          accelerometerStreamOverride: const Stream<AccelerometerEvent>.empty(),
        )..start();
        async.flushMicrotasks();
        expect(hostCalls, 0);
        tracker.dispose();
        own.close();
        async.flushMicrotasks();
        expect(ownCancels, 1);
      });
    },
  );

  test(
    'host corrected source retains slow intentional turns and acquisition timing',
    () {
      fakeAsync((async) {
        final host = StreamController<GyroscopeEvent>.broadcast();
        final gravity = StreamController<AccelerometerEvent>.broadcast();
        var calls = 0;
        HeadTracker.platformGyroscopeStreamFactory = () {
          calls++;
          return host.stream;
        };
        final target = _Target();
        final tracker = HeadTracker(
          target: target,
          predictionMs: 0,
          jitterDamping: false,
          accelerometerStreamOverride: gravity.stream,
        )..start();
        final start = DateTime(2026);
        // Delivery happens in one microtask burst; only acquisition time counts.
        for (var i = 0; i <= 100; i++) {
          final at = start.add(Duration(milliseconds: i * 10));
          gravity.add(AccelerometerEvent(9.81, 0, 0, at));
          host.add(GyroscopeEvent(.007, 0, 0, at));
        }
        async.flushMicrotasks();
        expect(calls, 1);
        expect(target.yaw, closeTo(.007, .000001));
        expect(tracker.gyroBiasX, 0); // Never absorb a slow turn as bias.
        tracker.dispose();
        host.close();
        gravity.close();
        async.flushMicrotasks();
      });
    },
  );
}
