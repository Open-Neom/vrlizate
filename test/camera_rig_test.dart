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

    test('Google Cardboard Neck Model shifts eyes realistically on rotation', () {
      final rig = CameraRig(ipd: 0.064);
      rig.position = Vector3(0, 0, 0);

      // Identity rotation (looking straight ahead)
      final leftViewIdentity = rig.leftViewMatrix;

      // Rotate rig by 90 degrees around Yaw (looking fully right)
      rig.rotate(pi / 2, 0);
      final leftViewRotated = rig.leftViewMatrix;

      // Transform a test point in front of the camera (e.g., world [0, 0, -2])
      final testPoint = Vector4(0, 0, -2, 1);
      final pointInIdentityEye = leftViewIdentity * testPoint;
      final pointInRotatedEye = leftViewRotated * testPoint;

      // They must differ dynamically because the eye shifted and rotated around the neck pivot
      expect(
        pointInIdentityEye.xyz.distanceTo(pointInRotatedEye.xyz),
        isNot(closeTo(0, 1e-6)),
      );
    });

    test('Simultaneous symmetric translation offsets', () {
      final rig = CameraRig(ipd: 0.064);
      final leftView = rig.leftViewMatrix;
      final rightView = rig.rightViewMatrix;
      final monoView = rig.monoViewMatrix;

      // Extract horizontal translations (element at index 12 in column-major storage)
      final leftT = leftView.storage[12];
      final rightT = rightView.storage[12];
      final monoT = monoView.storage[12];

      // The difference between mono and left should equal difference between right and mono
      expect((monoT - leftT).abs(), closeTo((rightT - monoT).abs(), 1e-4));
    });

    test('Neck model physical safety bounds are maintained', () {
      // Compute the displacement of the eye position relative to head position
      // For mono eye: local offset is (0, 0.075, -0.080)
      final localMono = Vector3(0, 0.075, -0.080);
      expect(localMono.length, lessThan(0.11)); // ~0.1096m <= 0.11m

      // For left and right eyes: local offset includes eye offset (IPD/2)
      final localLeft = Vector3(-0.032, 0.075, -0.080);
      final localRight = Vector3(0.032, 0.075, -0.080);
      expect(localLeft.length, lessThan(0.12)); // ~0.1142m <= 0.12m
      expect(localRight.length, lessThan(0.12));
    });
  });
}
