import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/core/camera/camera_rig.dart';
import 'package:vrlizate/core/input/background_isolate.dart';
import 'package:vrlizate/core/input/head_tracking_fusion.dart';

void main() {
  HeadTrackingFusion fusion() => HeadTrackingFusion()
    ..predictionMs = 0
    ..jitterDamping = false;

  for (final (name, x, y, z) in <(String, double, double, double)>[
    ('landscape X+', 1, 0, 0),
    ('landscape X-', -1, 0, 0),
    ('portrait Y+', 0, 1, 0),
    ('portrait Y-', 0, -1, 0),
    ('horizontal Z+', 0, 0, 1),
    ('horizontal Z-', 0, 0, -1),
  ]) {
    test(
      '$name retains its heading after rotation and five seconds at rest',
      () {
        final f = fusion();
        final rig = CameraRig();
        expect(f.updateGravity(x * 9.81, y * 9.81, z * 9.81), isTrue);
        void sample(int i, double rate) {
          f.addGyroscope(x * rate, y * rate, i * 10000, z: z * rate);
          rig.rotate(f.dYaw, f.dPitch);
          if (f.absolutePitch case final pitch?) rig.setPitch(pitch);
        }

        sample(0, 0);
        for (var i = 1; i <= 100; i++) {
          sample(i, pi / 2);
        }
        final expectedYaw = z == 0 ? pi / 2 : 0.0;
        expect(rig.yaw, closeTo(expectedYaw, 1e-10));
        final pitchAfterTurn = rig.pitch;
        for (var i = 101; i <= 600; i++) {
          sample(i, 0);
        }
        expect(rig.yaw, closeTo(expectedYaw, 1e-10));
        expect(rig.pitch, closeTo(pitchAfterTurn, 1e-10));
        // Both landscape signs and both portrait signs look level. At the
        // physical Z poles the elevated pitch is real, rather than a pi wrap.
        if (z == 0) expect(rig.pitch, closeTo(0, 1e-10));
      },
    );
  }

  test('forward-axis roll at 45 degrees does not turn azimuth', () {
    final f = fusion();
    f.updateGravity(9.81 / sqrt2, 0, 9.81 / sqrt2);
    var yaw = 0.0;
    for (var i = 0; i <= 100; i++) {
      f.addGyroscope(0, 0, i * 10000, z: 1);
      yaw += f.dYaw;
    }
    expect(yaw, 0);
  });

  test('world-vertical yaw at 45 degrees retains unit angular speed', () {
    final f = fusion();
    f.updateGravity(9.81 / sqrt2, 0, 9.81 / sqrt2);
    var yaw = 0.0;
    for (var i = 0; i <= 100; i++) {
      f.addGyroscope(1 / sqrt2, 0, i * 10000, z: 1 / sqrt2);
      yaw += f.dYaw;
    }
    expect(yaw, closeTo(1, 1e-10));
  });

  test('near a vertical-look pole heading stays finite and stationary', () {
    final f = fusion();
    const tilt = 89 * pi / 180;
    f.updateGravity(cos(tilt) * 9.81, 0, sin(tilt) * 9.81);
    for (var i = 0; i <= 100; i++) {
      f.addGyroscope(1, 1, i * 10000, z: 1);
      expect(f.dYaw, 0);
      expect(f.absolutePitch!.isFinite, isTrue);
    }
  });

  test('real pitch tilt has the same sign in four screen orientations', () {
    for (final (x, y) in <(double, double)>[(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final f = fusion();
      var yaw = 0.0;
      f.updateGravity(x * 9.81, y * 9.81, 0);
      f.addGyroscope(0, 0, 0);
      for (var i = 1; i <= 200; i++) {
        final tilt = i * 0.0015;
        f.updateGravity(
          x * cos(tilt) * 9.81,
          y * cos(tilt) * 9.81,
          sin(tilt) * 9.81,
        );
        f.addGyroscope(-y * .15, x * .15, i * 10000);
        yaw += f.dYaw;
      }
      expect(f.absolutePitch, closeTo(.3, .003));
      expect(yaw, closeTo(0, 1e-10));
    }
  });

  test('losing portrait gravity preserves its last gyro basis', () {
    final f = fusion();
    f.updateGravity(0, 9.81, 0);
    f.addGyroscope(0, 0, 0);
    f.clearGravity();
    f.addGyroscope(0, .2, 10000);
    expect(f.dYaw, closeTo(.002, 1e-10));
    expect(f.dPitch, 0);
    expect(f.absolutePitch, isNull);
  });

  test('invalid gravity and nonfinite Z cannot corrupt orientation', () {
    final f = fusion();
    expect(f.updateGravity(0, 0, 0), isFalse);
    expect(f.updateGravity(double.nan, 9.81, 0), isFalse);
    expect(f.updateGravity(0, double.infinity, 0), isFalse);
    expect(f.updateGravity(0, -9.81, 0), isTrue);
    f.addGyroscope(0, 0, 0);
    expect(f.addGyroscope(0, -.2, 10000, z: double.nan), isFalse);
    f.addGyroscope(0, -.2, 10000);
    expect(f.dYaw, closeTo(.002, 1e-10));
    expect(f.absolutePitch, closeTo(0, 1e-10));
  });

  test(
    'worker accepts appended gyro Z and offset Z without changing revisions',
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
      port.send([0, 1.0, 0.0, 0.0, 0.0, 1.0, false, 4, .0005]);
      port.send([1, 9.81 / sqrt2, 0.0, 9.81 / sqrt2]);
      port.send([2, 1 / sqrt2, 0.0, 0, 4, 1.0005]);
      expect(
        await messages.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      // A NaN in the optional Z tail must be rejected, without emitting a
      // spurious .005-radian event ahead of the valid .01-radian sample.
      port.send([2, 1 / sqrt2, 0.0, 5000, 4, double.nan]);
      port.send([2, 1 / sqrt2, 0.0, 10000, 4, 1.0005]);
      expect(
        await messages.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      final result = messages.current as List;
      expect(result[0], 4);
      expect(result[1], closeTo(.01, 1e-12));
      expect(result[2], 0);
    },
  );
}
