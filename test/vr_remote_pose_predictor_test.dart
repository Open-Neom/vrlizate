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
}

VrRemotePoseFrame _frame({required double angularVelocityY}) =>
    VrRemotePoseFrame(
      sequence: 1,
      senderTimestampMicroseconds: 1,
      orientation: Quaternion.identity(),
      angularVelocity: Vector3(0, angularVelocityY, 0),
    );
