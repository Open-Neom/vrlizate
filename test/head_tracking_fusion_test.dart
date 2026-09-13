import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/core/input/background_isolate.dart';
import 'package:vrlizate/core/input/head_tracking_fusion.dart';

void main() {
  HeadTrackingFusion createFusion() => HeadTrackingFusion()
    ..jitterDamping = false
    ..predictionMs = 0;

  test('100 Hz burst samples integrate one radian using acquisition time', () {
    final fusion = createFusion();
    var yaw = 0.0;
    for (var i = 0; i <= 100; i++) {
      fusion.addGyroscope(1, 0, i * 10000);
      yaw += fusion.dYaw;
    }
    expect(yaw, closeTo(1, 1e-10));
  });

  test('slow intentional turns are not learned as gyro bias', () {
    final fusion = createFusion();
    var yaw = 0.0;
    for (var i = 0; i <= 1000; i++) {
      fusion.addGyroscope(0.01, 0, i * 10000);
      yaw += fusion.dYaw;
    }
    expect(yaw, closeTo(0.1, 1e-10));
    expect(fusion.offsetX, 0);
  });

  test('duplicate, out-of-order and nonfinite samples do not poison time', () {
    final fusion = createFusion();
    fusion.addGyroscope(1, 0, 10000);
    expect(fusion.addGyroscope(1, 0, 10000), isFalse);
    expect(fusion.addGyroscope(1, 0, 0), isFalse);
    expect(fusion.addGyroscope(double.nan, 0, 20000), isFalse);
    fusion.addGyroscope(1, 0, 20000);
    expect(fusion.dYaw, closeTo(0.01, 1e-10));
  });

  test('large sensor gaps reset integration instead of extrapolating', () {
    final fusion = createFusion();
    fusion.addGyroscope(1, 0, 0);
    fusion.addGyroscope(1, 0, 10000);
    expect(fusion.dYaw, closeTo(0.01, 1e-10));
    fusion.addGyroscope(1, 0, 2000000);
    expect(fusion.dYaw, 0);
    fusion.addGyroscope(1, 0, 2010000);
    expect(fusion.dYaw, closeTo(0.01, 1e-10));
  });

  test('no pitch snap until measured gravity is plausible', () {
    final fusion = createFusion();
    expect(fusion.updateGravity(0, 0, 0), isFalse);
    expect(fusion.updateGravity(double.nan, 0, 9.8), isFalse);
    expect(fusion.updateGravity(50, 0, 0), isFalse);
    fusion.addGyroscope(0, 1, 0);
    expect(fusion.absolutePitch, isNull);
    fusion.addGyroscope(0, 1, 10000);
    expect(fusion.absolutePitch, isNull);
    expect(fusion.dPitch, closeTo(0.01, 1e-10));
    expect(fusion.updateGravity(9.8, 0, 0), isTrue);
    fusion.addGyroscope(0, 0, 20000);
    expect(fusion.absolutePitch, 0);
  });

  test('reset preserves gravity for recenter and clear reset discards it', () {
    final fusion = createFusion()..pitchGain = 1.3;
    fusion.updateGravity(9.8 * cos(0.3), 0, 9.8 * sin(0.3));
    fusion.addGyroscope(1, 0, 0);
    fusion.addGyroscope(1, 0, 10000);
    fusion.reset();
    fusion.addGyroscope(1, 0, 20000);
    expect(fusion.dYaw, 0);
    expect(fusion.absolutePitch, closeTo(0.39, 1e-10));
    fusion.reset(clearGravity: true);
    fusion.addGyroscope(1, 0, 30000);
    expect(fusion.absolutePitch, isNull);
  });

  test('damping preserves slow motion at high sensor sample rates', () {
    final fusion = HeadTrackingFusion()..predictionMs = 0;
    var yaw = 0.0;
    for (var i = 0; i <= 1000; i++) {
      fusion.addGyroscope(0.01, 0, i * 1000);
      yaw += fusion.dYaw;
    }
    expect(yaw, closeTo(0.01, 0.00001));
  });

  test('losing gravity continues relative pitch without an absolute snap', () {
    final fusion = createFusion();
    fusion.updateGravity(9.8 * cos(0.3), 0, 9.8 * sin(0.3));
    fusion.addGyroscope(0, 0, 0);
    fusion.clearGravity();
    fusion.addGyroscope(0, 1, 10000);
    expect(fusion.absolutePitch, isNull);
    expect(fusion.dPitch, closeTo(0.01, 1e-10));
  });

  test('pitch gain clamp remains continuous when gravity is lost', () {
    final fusion = createFusion()..pitchGain = 2;
    fusion.updateGravity(0, 0, 9.8);
    fusion.addGyroscope(0, 0, 0);
    expect(fusion.absolutePitch, 1.45);
    fusion.clearGravity();
    fusion.addGyroscope(0, 0, 10000);
    expect(fusion.dPitch, 0);
  });

  test(
    'worker matches main fusion signs, pitch gain, damping and resets',
    () async {
      final worker = BackgroundIsolate.create();
      final messages = StreamIterator<dynamic>(worker.messages);
      addTearDown(() async {
        await messages.cancel();
        worker.dispose();
      });
      await worker.start(headTrackingFusionEntry);
      expect(
        await messages.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      final dynamic port = messages.current;
      port.send([0, 1.2, 15.0, 0.01, -0.01, 1.3, true, 4]);
      port.send([1, 9.8 * cos(0.3), 0.0, 9.8 * sin(0.3)]);
      final fusion = HeadTrackingFusion()
        ..sensitivity = 1.2
        ..pitchGain = 1.3
        ..offsetX = 0.01
        ..offsetY = -0.01;
      fusion.updateGravity(9.8 * cos(0.3), 0, 9.8 * sin(0.3));
      for (var i = 0; i < 5; i++) {
        port.send([2, 0.4, 0.2, i * 10000, 4]);
        fusion.addGyroscope(0.4, 0.2, i * 10000);
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 3)),
          isTrue,
        );
        final result = messages.current as List;
        expect(result[0], 4);
        expect(result[1], closeTo(fusion.dYaw, 1e-12));
        expect(result[2], closeTo(fusion.dPitch, 1e-12));
        expect(result[3], closeTo(fusion.absolutePitch!, 1e-12));
      }
      port.send([3, 5]);
      port.send([2, 0.4, 0.2, 50000, 4]); // Stale revision must not emit.
      port.send([2, 0.4, 0.2, 50000, 5]);
      expect(
        await messages.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      final result = messages.current as List;
      expect(result[0], 5);
      expect(result[1], 0);
      expect(result[3], closeTo(0.39, 1e-12));
    },
  );

  test('disposing while worker is spawning is safe', () async {
    final worker = BackgroundIsolate.create();
    final started = worker.start(headTrackingFusionEntry);
    worker.dispose();
    await started;
    worker.dispose();
  });
}
