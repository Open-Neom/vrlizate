import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('VrControllerArmModel', () {
    test('keeps the established right-hand rest position', () {
      final rig = CameraRig();
      final model = VrControllerArmModel();
      final output = Vector3.zero();

      model.update(
        cameraRig: rig,
        controllerOrientation: Quaternion.identity(),
        dt: 1 / 60,
        out: output,
      );

      expect(output.x, closeTo(0.25, 1e-6));
      expect(output.y, closeTo(-0.24, 1e-6));
      expect(output.z, closeTo(-0.55, 1e-6));
    });

    test('mirrors rest position for a left-handed controller', () {
      final model = VrControllerArmModel(
        handedness: VrControllerHandedness.left,
      );
      final output = Vector3.zero();

      model.update(
        cameraRig: CameraRig(),
        controllerOrientation: Quaternion.identity(),
        dt: 0,
        out: output,
      );

      expect(output.x, closeTo(-0.25, 1e-6));
    });

    test('turning the controller moves the virtual hand within bounds', () {
      final rig = CameraRig();
      final model = VrControllerArmModel(responsiveness: 20);
      final output = Vector3.zero();
      model.update(
        cameraRig: rig,
        controllerOrientation: Quaternion.identity(),
        dt: 1 / 60,
        out: output,
      );

      final yaw = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2);
      model.update(
        cameraRig: rig,
        controllerOrientation: yaw,
        dt: 1 / 60,
        out: output,
      );

      expect(output.x, lessThan(0.25));
      expect(output.x, greaterThanOrEqualTo(0.13));
      expect(output.z, greaterThan(-0.55));
      expect(output.z, lessThanOrEqualTo(-0.47));
    });

    test('head translation is applied immediately, without arm lag', () {
      final rig = CameraRig();
      final model = VrControllerArmModel();
      final before = Vector3.zero();
      final after = Vector3.zero();
      model.update(
        cameraRig: rig,
        controllerOrientation: Quaternion.identity(),
        dt: 1 / 60,
        out: before,
      );

      rig.position = Vector3(1, 2, 3);
      model.update(
        cameraRig: rig,
        controllerOrientation: Quaternion.identity(),
        dt: 1 / 60,
        out: after,
      );

      expect(after.x - before.x, closeTo(1, 1e-6));
      expect(after.y - before.y, closeTo(2, 1e-6));
      expect(after.z - before.z, closeTo(3, 1e-6));
    });
  });
}
