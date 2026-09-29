import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vrlizate/vrlizate.dart';

class MockRotationTarget implements RotationTarget {
  final List<List<double>> rotateCalls = [];
  final List<double> pitchCalls = [];
  int resetCount = 0;

  @override
  void rotate(double dTheta, double dPhi) {
    rotateCalls.add([dTheta, dPhi]);
  }

  @override
  void reset() {
    resetCount++;
  }

  @override
  void recenter() {
    resetCount++;
  }

  @override
  void setOrientation(double yaw, double pitch) {}

  @override
  void setPitch(double pitch) => pitchCalls.add(pitch);
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
        useIsolate: false,
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
        final now = DateTime(2026);
        for (var i = 0; i <= 80; i++) {
          final at = now.add(Duration(milliseconds: i * 10));
          accelController.add(AccelerometerEvent(9.81, 0, 0, at));
          gyroController.add(GyroscopeEvent(.0006, -.0005, 0, at));
          async.flushMicrotasks();
        }
        expect(tracker.isCalibrating, isFalse);
        expect(tracker.calibrationStatus, 'accepted');
        expect(tracker.gyroBiasX, closeTo(.0006, 1e-12));
        expect(tracker.gyroBiasY, closeTo(-.0005, 1e-12));
        target.rotateCalls.clear();
        for (var i = 81; i <= 180; i++) {
          final at = now.add(Duration(milliseconds: i * 10));
          accelController.add(AccelerometerEvent(9.81, 0, 0, at));
          gyroController.add(GyroscopeEvent(.0006, -.0005, 0, at));
          async.flushMicrotasks();
        }
        expect(target.rotateCalls, isEmpty);
      });
    });

    test('S25 moved startup cannot create 26.7 degrees per second drift', () {
      fakeAsync((async) {
        tracker.predictionMs = 0;
        tracker.jitterDamping = false;
        tracker.start();
        final now = DateTime(2026);
        void sample(int us, double x, double y) {
          final at = now.add(Duration(microseconds: us));
          accelController.add(AccelerometerEvent(9.81, 0, 0, at));
          gyroController.add(GyroscopeEvent(x, y, 0, at));
          async.flushMicrotasks();
        }

        for (var i = 0; i < 451; i++) {
          sample(i * 2200, -.46654729783161236, .30278677501338985);
        }
        expect(tracker.gyroBiasX, 0);
        expect(tracker.gyroBiasY, 0);
        expect(tracker.isCalibrating, isTrue);
        target.rotateCalls.clear();
        // The real phone stopped; there must be no artificial opposite turn.
        for (var i = 0; i <= 3000; i++) {
          sample(1000000 + i * 10000, 0, 0);
        }
        expect(target.rotateCalls, isEmpty);
        expect(tracker.calibrationStatus, 'accepted');
        tracker.recenter();
        for (var i = 0; i <= 100; i++) {
          sample(32000000 + i * 10000, 0, 0);
        }
        expect(target.rotateCalls, isEmpty);
        expect(tracker.gyroBiasX, 0);
      });
    });

    for (final rate in [.003, .004]) {
      test(
        'startup turn at $rate rad/s stops without learned reverse drift',
        () {
          fakeAsync((async) {
            tracker.predictionMs = 0;
            tracker.jitterDamping = false;
            tracker.start();
            final now = DateTime(2026);
            void sample(int i, double x) {
              final at = now.add(Duration(milliseconds: i * 10));
              accelController.add(AccelerometerEvent(9.81, 0, 0, at));
              gyroController.add(GyroscopeEvent(x, 0, 0, at));
              async.flushMicrotasks();
            }

            for (var i = 0; i <= 1000; i++) {
              sample(i, rate);
            }
            expect(tracker.gyroBiasX, 0);
            expect(
              target.rotateCalls.fold<double>(0, (sum, v) => sum + v[0]),
              closeTo(rate * 10, 1e-10),
            );
            target.rotateCalls.clear();
            for (var i = 1001; i <= 4000; i++) {
              sample(i, 0);
            }
            expect(target.rotateCalls, isEmpty);
            expect(tracker.gyroBiasX.abs(), lessThanOrEqualTo(.001));
          });
        },
      );
    }

    test(
      'pending start and recenter calibrations preserve slow intentional yaw',
      () {
        fakeAsync((async) {
          tracker.predictionMs = 0;
          tracker.jitterDamping = false;
          tracker.start();
          final now = DateTime(2026);
          for (var i = 0; i <= 1000; i++) {
            final at = now.add(Duration(milliseconds: i * 10));
            accelController.add(AccelerometerEvent(9.81, 0, 0, at));
            gyroController.add(GyroscopeEvent(.01, 0, 0, at));
            async.flushMicrotasks();
          }
          expect(
            target.rotateCalls.fold<double>(0, (sum, v) => sum + v[0]),
            closeTo(.1, 1e-10),
          );
          expect(tracker.gyroBiasX, 0);
          expect(tracker.isCalibrating, isTrue);
          tracker.recenter();
          target.rotateCalls.clear();
          for (var i = 1001; i <= 2001; i++) {
            final at = now.add(Duration(milliseconds: i * 10));
            accelController.add(AccelerometerEvent(9.81, 0, 0, at));
            gyroController.add(GyroscopeEvent(.01, 0, 0, at));
            async.flushMicrotasks();
          }
          expect(
            target.rotateCalls.fold<double>(0, (sum, v) => sum + v[0]),
            closeTo(.1, 1e-10),
          );
          expect(tracker.gyroBiasX, 0);
        });
      },
    );

    test(
      'restart and recenter preserve valid bias until a new window succeeds',
      () {
        fakeAsync((async) {
          tracker.start();
          final now = DateTime(2026);
          void sample(int ms, double rate) {
            final at = now.add(Duration(milliseconds: ms));
            accelController.add(AccelerometerEvent(9.81, 0, 0, at));
            gyroController.add(GyroscopeEvent(rate, 0, 0, at));
            async.flushMicrotasks();
          }

          for (var i = 0; i <= 80; i++) {
            sample(i * 10, .0006);
          }
          expect(tracker.gyroBiasX, closeTo(.0006, 1e-12));
          tracker.stop();
          tracker.start();
          expect(tracker.gyroBiasX, closeTo(.0006, 1e-12));
          for (var i = 0; i <= 80; i++) {
            sample(1000 + i * 10, .2);
          }
          expect(tracker.isCalibrating, isTrue);
          expect(tracker.gyroBiasX, closeTo(.0006, 1e-12));
          tracker.recenter();
          expect(tracker.gyroBiasX, closeTo(.0006, 1e-12));
          for (var i = 0; i <= 80; i++) {
            sample(2000 + i * 10, .0002);
          }
          expect(tracker.isCalibrating, isFalse);
          expect(tracker.gyroBiasX, closeTo(.0002, 1e-12));
        });
      },
    );

    test('stop cancels all subscriptions and inactivates tracker', () {
      fakeAsync((async) {
        tracker.start();
        expect(tracker.isActive, isTrue);

        tracker.stop();
        expect(tracker.isActive, isFalse);
      });
    });

    test(
      'first gyro and recenter do not invent pitch without valid gravity',
      () {
        fakeAsync((async) {
          tracker.start();
          async.elapse(const Duration(seconds: 1));
          final now = DateTime(2026);
          accelController.add(AccelerometerEvent(0, 0, 0, now));
          accelController.add(AccelerometerEvent(double.nan, 0, 9.8, now));
          gyroController.add(GyroscopeEvent(0, 0, 0, now));
          async.flushMicrotasks();
          tracker.recenter();
          expect(target.pitchCalls, isEmpty);
          expect(target.resetCount, 1);
        });
      },
    );

    test('burst delivery integrates sensor timestamps, not wall clock', () {
      fakeAsync((async) {
        tracker.jitterDamping = false;
        tracker.predictionMs = 0;
        tracker.start();
        async.elapse(const Duration(seconds: 1));
        final now = DateTime(2026);
        for (var i = 0; i <= 100; i++) {
          gyroController.add(
            GyroscopeEvent(1, 0, 0, now.add(Duration(milliseconds: i * 10))),
          );
        }
        async.flushMicrotasks();
        expect(
          target.rotateCalls.fold<double>(0, (sum, v) => sum + v[0]),
          closeTo(1, 1e-8),
        );
      });
    });

    test(
      'lost gyro unlocks touch and resumes without integrating missing time',
      () {
        fakeAsync((async) {
          tracker.jitterDamping = false;
          tracker.predictionMs = 0;
          tracker.start();
          async.elapse(const Duration(seconds: 1));
          final now = DateTime(2026);
          gyroController.add(GyroscopeEvent(1, 0, 0, now));
          async.flushMicrotasks();
          expect(tracker.isGyroscopeActive, isTrue);
          async.elapse(const Duration(milliseconds: 800));
          expect(tracker.isGyroscopeActive, isFalse);
          tracker.applyTouchDelta(10, 0);
          expect(target.rotateCalls.last[0], -0.05);
          target.rotateCalls.clear();
          gyroController.add(
            GyroscopeEvent(1, 0, 0, now.add(const Duration(seconds: 2))),
          );
          async.flushMicrotasks();
          expect(tracker.isGyroscopeActive, isTrue);
          expect(target.rotateCalls, isEmpty);
        });
      },
    );

    test('stream error and completion release touch fallback', () {
      fakeAsync((async) {
        tracker.start();
        gyroController.add(GyroscopeEvent(0, 0, 0, DateTime(2026)));
        async.flushMicrotasks();
        gyroController.addError(StateError('sensor disconnected'));
        async.flushMicrotasks();
        expect(tracker.isGyroscopeActive, isFalse);
        gyroController.add(GyroscopeEvent(0, 0, 0, DateTime(2026)));
        async.flushMicrotasks();
        expect(tracker.isGyroscopeActive, isTrue);
        gyroController.close();
        async.flushMicrotasks();
        expect(tracker.isGyroscopeActive, isFalse);
      });
    });

    test(
      'stop cancels timers; pending calibration never freezes a restarted stream',
      () {
        fakeAsync((async) {
          tracker.start();
          async.elapse(const Duration(milliseconds: 500));
          tracker.stop();
          expect(async.periodicTimerCount, 0);
          expect(async.nonPeriodicTimerCount, 0);
          tracker.start();
          async.elapse(const Duration(milliseconds: 600));
          final now = DateTime(2026);
          gyroController.add(GyroscopeEvent(0.1, 0, 0, now));
          gyroController.add(
            GyroscopeEvent(
              0.1,
              0,
              0,
              now.add(const Duration(milliseconds: 10)),
            ),
          );
          async.flushMicrotasks();
          expect(
            target.rotateCalls,
            isNotEmpty,
            reason: 'Tracking continues while movement prevents calibration',
          );
          expect(tracker.gyroBiasX, 0);
          expect(tracker.isCalibrating, isTrue);
          target.rotateCalls.clear();
          tracker.stop();
          async.elapse(const Duration(seconds: 2));
          expect(tracker.isGyroscopeActive, isFalse);
          expect(target.rotateCalls, isEmpty);
        });
      },
    );

    test(
      'touchDelta delegates directly to target when gyroscope is inactive',
      () {
        tracker.isGyroscopeActive = false;
        tracker.applyTouchDelta(10, 20, touchSensitivity: 0.1);
        expect(target.rotateCalls.length, equals(1));
        expect(target.rotateCalls.first[0], equals(-1.0));
        expect(target.rotateCalls.first[1], equals(-2.0));
      },
    );

    test('touchDelta ignores touch when gyroscope is active', () {
      tracker.isGyroscopeActive = true;
      tracker.applyTouchDelta(10, 20, touchSensitivity: 0.1);
      expect(target.rotateCalls.isEmpty, isTrue);
    });

    test('stale or failed gravity is not reused by recenter', () {
      fakeAsync((async) {
        tracker.start();
        final now = DateTime(2026);
        accelController.add(AccelerometerEvent(9.8, 0, 0, now));
        async.flushMicrotasks();
        tracker.recenter();
        expect(target.pitchCalls.last, 0);
        target.pitchCalls.clear();
        async.elapse(const Duration(milliseconds: 800));
        tracker.recenter();
        expect(target.pitchCalls, isEmpty);
        accelController.add(AccelerometerEvent(9.8, 0, 0, now));
        async.flushMicrotasks();
        target.pitchCalls.clear();
        accelController.addError(StateError('accelerometer lost'));
        async.flushMicrotasks();
        tracker.recenter();
        expect(target.pitchCalls, isEmpty);
      });
    });

    test(
      'isolate recenter uses measured gravity and stop rejects queued work',
      () async {
        tracker.dispose();
        tracker = HeadTracker(
          target: target,
          useIsolate: true,
          gyroscopeStreamOverride: gyroController.stream,
          accelerometerStreamOverride: accelController.stream,
        )..start();
        accelController.add(AccelerometerEvent(9.8, 0, 0, DateTime(2026)));
        await Future<void>.delayed(Duration.zero);
        tracker.recenter();
        expect(target.pitchCalls.last, 0);
        tracker.stop();
        final pitchCount = target.pitchCalls.length;
        final rotationCount = target.rotateCalls.length;
        gyroController.add(GyroscopeEvent(1, 0, 0, DateTime(2026)));
        accelController.add(AccelerometerEvent(0, 0, 9.8, DateTime(2026)));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(target.pitchCalls.length, pitchCount);
        expect(target.rotateCalls.length, rotationCount);
        expect(tracker.isGyroscopeActive, isFalse);
      },
    );
  });
}
