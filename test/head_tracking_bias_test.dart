import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/core/input/head_tracking_bias.dart';

void main() {
  void sample(
    HeadTrackingBiasEstimator estimator,
    int us, {
    double x = .0006,
    double y = -.0004,
    double z = .0002,
    double gx = 9.81,
    double gy = 0,
    double gz = 0,
  }) {
    estimator.addGravity(gx, gy, gz, us);
    estimator.addGyroscope(x, y, z, us);
  }

  test(
    'requires unique acquisition timestamps, span and sufficient samples',
    () {
      final estimator = HeadTrackingBiasEstimator()..request();
      for (var i = 0; i < 500; i++) {
        sample(estimator, 1000);
      }
      expect(estimator.sampleCount, 1);
      expect(estimator.accepted, isFalse);
      for (var i = 1; i < 80; i++) {
        sample(estimator, 1000 + i * 10000);
      }
      expect(estimator.accepted, isFalse);
      sample(estimator, 801000);
      expect(estimator.accepted, isTrue);
      expect(estimator.biasX, closeTo(.0006, 1e-12));
      expect(estimator.biasY, closeTo(-.0004, 1e-12));
    },
  );

  test('rejects measured S25 startup movement then accepts real rest', () {
    final estimator = HeadTrackingBiasEstimator()..request();
    for (var i = 0; i < 451; i++) {
      sample(
        estimator,
        i * 2200,
        x: -.46654729783161236,
        y: .30278677501338985,
        z: 0,
      );
    }
    expect(estimator.accepted, isFalse);
    expect(estimator.status, 'gyro_moving');
    expect(estimator.biasX, 0);
    for (var i = 0; i <= 80; i++) {
      sample(estimator, 1000000 + i * 10000, x: .0005, y: -.0003, z: 0);
    }
    expect(estimator.accepted, isTrue);
    expect(estimator.biasX, closeTo(.0005, 1e-12));
  });

  test('slow .003/.004/.01 yaw and Z turns are never accepted as bias', () {
    for (final (rate, zTurn) in [
      (.003, false),
      (.004, false),
      (.01, false),
      (.003, true),
      (.01, true),
    ]) {
      final estimator = HeadTrackingBiasEstimator()..request();
      for (var i = 0; i <= 1000; i++) {
        sample(
          estimator,
          i * 10000,
          x: zTurn ? 0 : rate,
          y: 0,
          z: zTurn ? rate : 0,
        );
      }
      expect(estimator.accepted, isFalse);
      expect(estimator.biasX, 0);
    }
  });

  test(
    'variance, changing gravity and implausible acceleration veto windows',
    () {
      final noisy = HeadTrackingBiasEstimator()..request();
      final moving = HeadTrackingBiasEstimator()..request();
      final accelerating = HeadTrackingBiasEstimator()..request();
      for (var i = 0; i <= 100; i++) {
        sample(noisy, i * 10000, x: i.isEven ? .015 : -.015);
        sample(moving, i * 10000, gy: i * .01);
        sample(accelerating, i * 10000, gx: 13);
      }
      expect(noisy.accepted, isFalse);
      expect(moving.accepted, isFalse);
      expect(accelerating.accepted, isFalse);
    },
  );

  test('a paused acquisition or stale gravity cannot complete a window', () {
    final estimator = HeadTrackingBiasEstimator()..request();
    for (var i = 0; i < 40; i++) {
      sample(estimator, i * 10000);
    }
    sample(estimator, 1000000);
    expect(estimator.sampleCount, 1);
    for (var i = 1; i <= 100; i++) {
      estimator.addGyroscope(.003, 0, 0, 1000000 + i * 10000);
    }
    expect(estimator.accepted, isFalse);
    expect(estimator.status, 'waiting_for_gravity');
  });

  test('accepted bias never adapts during subsequent motion', () {
    final estimator = HeadTrackingBiasEstimator()..request();
    for (var i = 0; i <= 80; i++) {
      sample(estimator, i * 10000);
    }
    final bias = estimator.biasX;
    for (var i = 81; i <= 1080; i++) {
      sample(estimator, i * 10000, x: .01);
    }
    expect(estimator.accepted, isTrue);
    expect(estimator.biasX, bias);
    estimator.request();
    expect(estimator.accepted, isFalse);
  });
}
