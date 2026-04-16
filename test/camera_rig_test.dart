import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('CameraRig', () {
    test('default position is origin', () {
      final rig = CameraRig();
      expect(rig.position.x, closeTo(0, 1e-6));
      expect(rig.position.y, closeTo(0, 1e-6));
      expect(rig.position.z, closeTo(0, 1e-6));
    });

    test('left and right view matrices differ by IPD', () {
      final rig = CameraRig(ipd: 0.064);
      final leftView = rig.leftViewMatrix;
      final rightView = rig.rightViewMatrix;

      // They should NOT be identical
      expect(leftView.storage[12], isNot(closeTo(rightView.storage[12], 1e-6)));
    });

    test('mono view matrix is between left and right', () {
      final rig = CameraRig(ipd: 0.064);
      rig.position = Vector3(0, 0, 5);

      final leftT = rig.leftViewMatrix.storage[12];
      final rightT = rig.rightViewMatrix.storage[12];
      final monoT = rig.monoViewMatrix.storage[12];

      // Mono should be between left and right
      expect(monoT, greaterThanOrEqualTo(min(leftT, rightT)));
      expect(monoT, lessThanOrEqualTo(max(leftT, rightT)));
    });

    test('off-axis projection is asymmetric', () {
      final rig = CameraRig(ipd: 0.064);
      final leftProj = rig.leftProjectionMatrix(1.0);
      final rightProj = rig.rightProjectionMatrix(1.0);

      // The horizontal offset (m[8]) should differ
      expect(leftProj.storage[8], isNot(closeTo(rightProj.storage[8], 1e-6)));
    });

    test('zero IPD produces identical left/right views', () {
      final rig = CameraRig(ipd: 0);
      final leftView = rig.leftViewMatrix;
      final rightView = rig.rightViewMatrix;

      for (var i = 0; i < 16; i++) {
        expect(leftView.storage[i], closeTo(rightView.storage[i], 1e-6));
      }
    });

    test('frustum from monoViewProjection does not produce NaN', () {
      final rig = CameraRig();
      rig.position = Vector3(0, 1.6, 5);
      rig.lookAt(Vector3(0, 0, 0));

      final vp = rig.monoViewProjection(16 / 9);
      final frustum = VrFrustum.fromViewProjection(vp);

      for (final plane in frustum.planes) {
        expect(plane.x.isNaN, isFalse);
        expect(plane.y.isNaN, isFalse);
        expect(plane.z.isNaN, isFalse);
        expect(plane.w.isNaN, isFalse);
      }
    });

    test('rotate changes forward direction', () {
      final rig = CameraRig();
      final forwardBefore = rig.headTransform.forward.clone();
      rig.rotate(pi / 4, 0); // 45 degrees yaw
      final forwardAfter = rig.headTransform.forward;

      expect(forwardBefore.dot(forwardAfter), lessThan(0.95));
    });

    test('reset restores identity', () {
      final rig = CameraRig();
      rig.position = Vector3(10, 20, 30);
      rig.rotate(1, 1);
      rig.reset();

      expect(rig.position.x, closeTo(0, 1e-6));
      expect(rig.rotation.w, closeTo(1, 1e-4));
    });

    test('implements RotationTarget interface', () {
      final rig = CameraRig();
      // Should compile and work as RotationTarget
      final RotationTarget target = rig;
      target.rotate(0.1, 0.1);
      target.reset();
    });
  });
}
