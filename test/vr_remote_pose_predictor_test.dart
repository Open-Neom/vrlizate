import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('VrRemotePosePredictor', () {
    test('predicts from angular velocity without allocating output', () {
      var now = 1000000;
      final predictor = VrRemotePosePredictor(
        renderLead: Duration.zero,
        clock: () => now,
      );
      predictor.pushFrame(
        _frame(angularVelocityY: math.pi),
        receivedAtMicroseconds: now,
      );

      now += 50000;
      final output = Quaternion.identity();
      expect(predictor.predictTo(output), isTrue);

      const expectedAngle = math.pi * 0.05;
      expect(output.y, closeTo(math.sin(expectedAngle / 2), 1e-6));
      expect(output.w, closeTo(math.cos(expectedAngle / 2), 1e-6));
      expect(predictor.lastPredictionHorizon, const Duration(milliseconds: 50));
    });

    test('adds one-way latency and render lead, then clamps stale poses', () {
      var now = 2000000;
      final predictor = VrRemotePosePredictor(
        renderLead: const Duration(milliseconds: 5),
        maximumPrediction: const Duration(milliseconds: 40),
        clock: () => now,
      );
      predictor.updateLatency(const Duration(milliseconds: 20));
      predictor.pushFrame(
        _frame(angularVelocityY: 1),
        receivedAtMicroseconds: now,
      );

      now += 10000;
      predictor.predictTo(Quaternion.identity());
      expect(predictor.lastPredictionHorizon, const Duration(milliseconds: 25));

      now += 1000000;
      predictor.predictTo(Quaternion.identity());
      expect(predictor.lastPredictionHorizon, const Duration(milliseconds: 40));
    });

    test('smooths latency samples and reset removes the current pose', () {
      final predictor = VrRemotePosePredictor(
        latencySmoothing: 0.25,
        clock: () => 0,
      );
      predictor.updateLatency(const Duration(milliseconds: 20));
      predictor.updateLatency(const Duration(milliseconds: 60));
      expect(predictor.roundTripLatency, const Duration(milliseconds: 30));

      predictor.pushFrame(_frame(angularVelocityY: 0));
      expect(predictor.hasPose, isTrue);
      predictor.reset();
      expect(predictor.hasPose, isFalse);
      expect(predictor.predictTo(Quaternion.identity()), isFalse);
    });
  });

  group('optional remote orientation smoothing', () {
    Quaternion yaw(double radians) =>
        Quaternion.axisAngle(Vector3(0, 1, 0), radians);

    test('default forwards orientations without smoothing delay', () {
      final predictor = VrRemotePosePredictor(renderLead: Duration.zero);
      final output = Quaternion.identity();
      predictor.pushFrame(_frame(), receivedAtMicroseconds: 0);
      predictor.pushFrame(
        _frame(orientation: yaw(.6)),
        receivedAtMicroseconds: 10000,
      );
      predictor.predictTo(output, atMicroseconds: 10000);
      expect(_angleBetween(output, yaw(.6)), closeTo(0, 1e-6));
    });

    test('reduces stationary angular jitter', () {
      final predictor = VrRemotePosePredictor(
        renderLead: Duration.zero,
        smoothing: VrRemotePoseSmoothing(minCutoff: 1, beta: .02),
      );
      final output = Quaternion.identity();
      predictor.pushFrame(_frame(), receivedAtMicroseconds: 0);
      var filteredEnergy = 0.0;
      var rawEnergy = 0.0;
      for (var sample = 1; sample <= 200; sample++) {
        final angle = sample.isEven ? .01 : -.01;
        final time = sample * 10000;
        predictor.pushFrame(
          _frame(orientation: yaw(angle)),
          receivedAtMicroseconds: time,
        );
        predictor.predictTo(output, atMicroseconds: time);
        if (sample > 50) {
          final filteredAngle = _angleBetween(output, Quaternion.identity());
          filteredEnergy += filteredAngle * filteredAngle;
          rawEnergy += angle * angle;
        }
      }
      expect(filteredEnergy, lessThan(rawEnergy * .1));
    });

    test('adaptive cutoff follows a fast step sooner than a fixed cutoff', () {
      final fixed = VrRemotePosePredictor(
        renderLead: Duration.zero,
        smoothing: VrRemotePoseSmoothing(beta: 0),
      );
      final adaptive = VrRemotePosePredictor(
        renderLead: Duration.zero,
        smoothing: VrRemotePoseSmoothing(beta: .8),
      );
      final fixedOutput = Quaternion.identity();
      final adaptiveOutput = Quaternion.identity();
      fixed.pushFrame(_frame(), receivedAtMicroseconds: 0);
      adaptive.pushFrame(_frame(), receivedAtMicroseconds: 0);
      final target = yaw(.7);
      for (var sample = 1; sample <= 20; sample++) {
        final time = sample * 10000;
        final frame = _frame(orientation: target);
        fixed.pushFrame(frame, receivedAtMicroseconds: time);
        adaptive.pushFrame(frame, receivedAtMicroseconds: time);
        fixed.predictTo(fixedOutput, atMicroseconds: time);
        adaptive.predictTo(adaptiveOutput, atMicroseconds: time);
      }
      expect(
        _angleBetween(adaptiveOutput, target),
        lessThan(_angleBetween(fixedOutput, target) * .7),
      );
    });

    test('q and -q produce the same normalized trajectory across pi', () {
      final normal = VrRemotePosePredictor(
        renderLead: Duration.zero,
        smoothing: VrRemotePoseSmoothing(),
      );
      final alternating = VrRemotePosePredictor(
        renderLead: Duration.zero,
        smoothing: VrRemotePoseSmoothing(),
      );
      final a = Quaternion.identity();
      final b = Quaternion.identity();
      for (var sample = 0; sample < 100; sample++) {
        final pose = yaw(3.05 + sample * .003);
        final sign = sample.isEven ? 1.0 : -1.0;
        final equivalent = Quaternion(
          pose.x * sign,
          pose.y * sign,
          pose.z * sign,
          pose.w * sign,
        );
        final time = sample * 10000;
        normal.pushFrame(
          _frame(orientation: pose),
          receivedAtMicroseconds: time,
        );
        alternating.pushFrame(
          _frame(orientation: equivalent),
          receivedAtMicroseconds: time,
        );
        normal.predictTo(a, atMicroseconds: time);
        alternating.predictTo(b, atMicroseconds: time);
        expect(_angleBetween(a, b), closeTo(0, 1e-6));
        // Component storage is Float32, including the result of normalize().
        expect(b.length, closeTo(1, 1e-7));
      }
    });

    test(
      'Float32 length rounding does not trigger an angular discontinuity',
      () {
        final predictor = VrRemotePosePredictor(
          renderLead: Duration.zero,
          smoothing: VrRemotePoseSmoothing(
            beta: 0,
            discontinuityRadians: .0002,
          ),
        );
        final initial = yaw(.01);
        final target = yaw(.0101);
        final output = Quaternion.identity();
        predictor.pushFrame(
          _frame(orientation: initial),
          receivedAtMicroseconds: 0,
        );
        predictor.pushFrame(
          _frame(orientation: target),
          receivedAtMicroseconds: 10000,
        );
        predictor.predictTo(output, atMicroseconds: 10000);
        expect(
          _angleBetween(output, target),
          greaterThan(.00008),
          reason: 'a real 0.0001-radian step must be smoothed, not reset',
        );
        expect(_angleBetween(output, initial), lessThan(.00002));
      },
    );

    test(
      'gap, angular discontinuity and reset discard stale filter history',
      () {
        final predictor = VrRemotePosePredictor(
          renderLead: Duration.zero,
          smoothing: VrRemotePoseSmoothing(),
        );
        final output = Quaternion.identity();
        void push(double angle, int time) {
          predictor.pushFrame(
            _frame(orientation: yaw(angle)),
            receivedAtMicroseconds: time,
          );
          predictor.predictTo(output, atMicroseconds: time);
        }

        push(0, 0);
        push(.5, 10000);
        expect(_angleBetween(output, yaw(.5)), greaterThan(.1));
        push(.8, 260001); // Reception gap >250ms.
        expect(_angleBetween(output, yaw(.8)), closeTo(0, 1e-6));
        push(-1.2, 270001); // Recenter-like jump >90 degrees.
        expect(_angleBetween(output, yaw(-1.2)), closeTo(0, 1e-6));
        push(-1, 265001); // Non-monotonic reception time.
        expect(_angleBetween(output, yaw(-1)), closeTo(0, 1e-6));
        predictor.reset();
        expect(predictor.predictTo(output), isFalse);
        push(.2, 280001);
        expect(_angleBetween(output, yaw(.2)), closeTo(0, 1e-6));
      },
    );

    test('rejects invalid smoothing parameters', () {
      expect(() => VrRemotePoseSmoothing(minCutoff: 0), throwsArgumentError);
      expect(
        () => VrRemotePoseSmoothing(beta: double.nan),
        throwsArgumentError,
      );
      expect(
        () => VrRemotePoseSmoothing(derivativeCutoff: -1),
        throwsArgumentError,
      );
      expect(
        () => VrRemotePoseSmoothing(resetAfter: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => VrRemotePoseSmoothing(discontinuityRadians: math.pi + .1),
        throwsArgumentError,
      );
    });
  });
}

double _angleBetween(Quaternion a, Quaternion b) =>
    2 *
    math.acos(
      ((a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w) /
              math.sqrt(a.length2 * b.length2))
          .abs()
          .clamp(0.0, 1.0),
    );

VrRemotePoseFrame _frame({
  double angularVelocityY = 0,
  Quaternion? orientation,
}) => VrRemotePoseFrame(
  sequence: 1,
  senderTimestampMicroseconds: 1,
  orientation: orientation ?? Quaternion.identity(),
  angularVelocity: Vector3(0, angularVelocityY, 0),
);
