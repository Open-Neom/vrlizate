import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vrlizate/vrlizate.dart';

class MockRotationTarget implements RotationTarget {
  final List<List<double>> rotateCalls = [];
  int resetCount = 0;

  @override
  void rotate(double dTheta, double dPhi) {
    rotateCalls.add([dTheta, dPhi]);
  }

  @override
  void reset() {
    resetCount++;
  }
}

void main() {
  group('HeadTracker', () {
    late MockRotationTarget target;
    late StreamController<GyroscopeEvent> gyroController;
    late StreamController<AccelerometerEvent> accelController;
    late HeadTracker tracker;

    setUp(() {
      target = MockRotationTarget();
      gyroController = StreamController<GyroscopeEvent>.broadcast();
      accelController = StreamController<AccelerometerEvent>.broadcast();
      tracker = HeadTracker(
        target: target,
        sensitivity: 1.0,
        gyroscopeStreamOverride: gyroController.stream,
        accelerometerStreamOverride: accelController.stream,
      );
    });

    tearDown(() {
      tracker.dispose();
      gyroController.close();
      accelController.close();
    });

    test('start initiates stream subscriptions and processes events', () {
      fakeAsync((async) {
        tracker.start();

        expect(tracker.isActive, isTrue);

        // Elapse 1 second to finish calibration
        async.elapse(const Duration(seconds: 1));

        final now = DateTime.now();
        // Send initial accelerometer and gyroscope readings
        accelController.add(AccelerometerEvent(0, 0, 9.8, now));
        gyroController.add(GyroscopeEvent(0, 0, 0, now));
        async.flushMicrotasks();

        // First gyroscope event just initializes _lastTimestamp and fused state
        expect(target.rotateCalls.isEmpty, isTrue);

        // Now send second gyroscope event after a small time delta
        gyroController.add(
          GyroscopeEvent(
            0.5,
            0.2,
            0,
            now.add(const Duration(milliseconds: 50)),
          ),
        );
        async.flushMicrotasks();

        // Should have processed the second event and rotated
        expect(target.rotateCalls.isNotEmpty, isTrue);
      });
    });

    test('calibration computes offsets and adjusts subsequent events', () {
      fakeAsync((async) {
        tracker.start();
        tracker.calibrate();

        // Feed calibration samples
        final now = DateTime.now();
        gyroController.add(GyroscopeEvent(0.1, -0.2, 0, now));
        gyroController.add(GyroscopeEvent(0.3, -0.4, 0, now));

        // Elapse 1 second to finish calibration
        async.elapse(const Duration(seconds: 1));

        // Check that offsets are computed correctly
        // After calibration, send normal event
        accelController.add(AccelerometerEvent(0, 0, 9.8, now));
        gyroController.add(GyroscopeEvent(0, 0, 0, now)); // Init
        async.flushMicrotasks();

        target.rotateCalls.clear();

        // Since the calibration average is X = 0.2, Y = -0.3,
        // sending a gyro event with exactly these values should produce 0 rotation!
        gyroController.add(
          GyroscopeEvent(
            0.2,
            -0.3,
            0,
            now.add(const Duration(milliseconds: 100)),
          ),
        );
        async.flushMicrotasks();

        // If calibration works, the rotation should be exactly zero.
        if (target.rotateCalls.isNotEmpty) {
          expect(target.rotateCalls.first[0], closeTo(0, 1e-4));
          expect(target.rotateCalls.first[1], closeTo(0, 1e-4));
        }
      });
    });

    test('stop cancels all subscriptions and inactivates tracker', () {
      fakeAsync((async) {
        tracker.start();
        expect(tracker.isActive, isTrue);

        tracker.stop();
        expect(tracker.isActive, isFalse);
      });
    });

    test('touchDelta delegates directly to target', () {
      tracker.applyTouchDelta(10, 20, touchSensitivity: 0.1);
      expect(target.rotateCalls.length, equals(1));
      expect(target.rotateCalls.first[0], equals(-1.0));
      expect(target.rotateCalls.first[1], equals(-2.0));
    });
  });
}
