import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('WalkInPlaceDetector', () {
    test('detects steps from a sinusoidal head-bob signal', () {
      final detector = WalkInPlaceDetector(
        stepThreshold: 1.0,
        refractoryPeriod: const Duration(milliseconds: 250),
      );
      var steps = 0;
      detector.onStep = () => steps++;
      detector.reset();

      // Simulate 3 seconds of marching at ~2 Hz: gravity on -Z plus a
      // vertical bob of ±2.5 m/s². Sampled at 50 Hz.
      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 150; i++) {
        final t = i / 50.0;
        final bob = 2.5 * math.sin(2 * math.pi * 2.0 * t);
        detector.feedSample(
          0,
          0,
          -9.8 + bob,
          t0.add(Duration(milliseconds: i * 20)),
        );
      }

      // 3 s at 2 Hz = 6 bobs; refractory 250 ms allows all of them.
      expect(steps, greaterThanOrEqualTo(5));
      expect(steps, lessThanOrEqualTo(7));
      expect(detector.stepCount, steps);
      detector.dispose();
    });

    test('does not fire on noise below the threshold', () {
      final detector = WalkInPlaceDetector(stepThreshold: 2.0);
      var steps = 0;
      detector.onStep = () => steps++;
      detector.reset();

      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 200; i++) {
        final noise = 0.3 * math.sin(i * 1.7);
        detector.feedSample(
          0,
          0,
          -9.8 + noise,
          t0.add(Duration(milliseconds: i * 10)),
        );
      }

      expect(steps, 0);
      detector.dispose();
    });

    test('refractory period suppresses double-counting of one bob', () {
      final detector = WalkInPlaceDetector(
        stepThreshold: 1.0,
        refractoryPeriod: const Duration(milliseconds: 400),
      );
      detector.reset();

      final t0 = DateTime(2026, 1, 1);
      // One slow bob (1 Hz) sampled at 100 Hz: many samples above threshold
      // but only one step should be counted per bob.
      for (var i = 0; i < 200; i++) {
        final t = i / 100.0;
        final bob = 3.0 * math.sin(2 * math.pi * 1.0 * t);
        detector.feedSample(
          0,
          0,
          -9.8 + bob,
          t0.add(Duration(milliseconds: i * 10)),
        );
      }

      expect(detector.stepCount, 2); // Exactly two bobs in 2 s at 1 Hz.
      detector.dispose();
    });

    test('cadence is reported in steps per minute', () {
      final detector = WalkInPlaceDetector(
        stepThreshold: 1.0,
        refractoryPeriod: const Duration(milliseconds: 250),
      );
      double? lastCadence;
      detector.onCadenceChanged = (c) => lastCadence = c;
      detector.reset();

      final t0 = DateTime(2026, 1, 1);
      // 2 Hz stepping = 120 steps/min.
      for (var i = 0; i < 200; i++) {
        final t = i / 50.0;
        final bob = 2.5 * math.sin(2 * math.pi * 2.0 * t);
        detector.feedSample(
          0,
          0,
          -9.8 + bob,
          t0.add(Duration(milliseconds: i * 20)),
        );
      }

      expect(lastCadence, isNotNull);
      expect(lastCadence!, closeTo(120, 40));
      detector.dispose();
    });

    test('adapts to arbitrary device orientation via gravity estimation', () {
      final detector = WalkInPlaceDetector(stepThreshold: 1.0);
      detector.reset();

      final t0 = DateTime(2026, 1, 1);
      // Landscape in a viewer: gravity along -X instead of -Z.
      for (var i = 0; i < 150; i++) {
        final t = i / 50.0;
        final bob = 2.5 * math.sin(2 * math.pi * 2.0 * t);
        detector.feedSample(
          -9.8 + bob,
          0,
          0,
          t0.add(Duration(milliseconds: i * 20)),
        );
      }

      expect(detector.stepCount, greaterThanOrEqualTo(4));
      detector.dispose();
    });
  });

  group('WalkInPlaceLocomotion', () {
    test('moves the camera forward while steps are detected', () {
      final rig = CameraRig();
      final detector = WalkInPlaceDetector(stepThreshold: 1.0);
      final locomotion = WalkInPlaceLocomotion(
        cameraRig: rig,
        detector: detector,
        speed: 1.4,
      );
      detector.reset();

      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 150; i++) {
        final t = i / 50.0;
        final bob = 2.5 * math.sin(2 * math.pi * 2.0 * t);
        detector.feedSample(
          0,
          0,
          -9.8 + bob,
          t0.add(Duration(milliseconds: i * 20)),
        );
        locomotion.update(0.02);
      }

      expect(locomotion.currentVelocity, greaterThan(0));
      final moved = rig.position.length;
      expect(moved, greaterThan(0.1));

      locomotion.dispose();
    });

    test('velocity decays to zero when stepping stops', () {
      final rig = CameraRig();
      final detector = WalkInPlaceDetector(stepThreshold: 1.0);
      final locomotion = WalkInPlaceLocomotion(
        cameraRig: rig,
        detector: detector,
        deceleration: 4.0,
      );

      // Simulate an active cadence by forcing velocity via update loop.
      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 100; i++) {
        final t = i / 50.0;
        final bob = 2.5 * math.sin(2 * math.pi * 2.0 * t);
        detector.feedSample(
          0,
          0,
          -9.8 + bob,
          t0.add(Duration(milliseconds: i * 20)),
        );
        locomotion.update(0.02);
      }
      expect(locomotion.currentVelocity, greaterThan(0));

      // Stop stepping; advance time beyond the cadence window (4 s).
      for (var i = 0; i < 300; i++) {
        detector.feedSample(
          0,
          0,
          -9.8,
          t0.add(Duration(seconds: 5 + i * 20 ~/ 1000)),
        );
        locomotion.update(0.02);
      }
      expect(locomotion.currentVelocity, 0);

      locomotion.dispose();
    });

    test('moves along the head forward direction projected to the ground', () {
      final rig = CameraRig();
      rig.rotate(math.pi / 2, 0); // Yaw 90°.
      final detector = WalkInPlaceDetector(stepThreshold: 1.0);
      final locomotion = WalkInPlaceLocomotion(
        cameraRig: rig,
        detector: detector,
      );

      final before = rig.position.clone();
      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 150; i++) {
        final t = i / 50.0;
        final bob = 2.5 * math.sin(2 * math.pi * 2.0 * t);
        detector.feedSample(
          0,
          0,
          -9.8 + bob,
          t0.add(Duration(milliseconds: i * 20)),
        );
        locomotion.update(0.02);
      }

      final displacement = rig.position - before;
      final forward = rig.headTransform.forward;
      final groundForward = Vector3(forward.x, 0, forward.z)..normalize();
      final dir = displacement.normalized();
      expect(dir.dot(groundForward), closeTo(1.0, 1e-6));

      locomotion.dispose();
    });
  });
}
