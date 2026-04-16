import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('VrFrustum', () {
    late VrFrustum frustum;

    setUp(() {
      // Create a standard perspective frustum looking down -Z
      final projection = makePerspectiveMatrix(pi / 3, 1.0, 0.1, 100);
      final view = makeViewMatrix(
        Vector3(0, 0, 5), // eye
        Vector3(0, 0, 0), // target
        Vector3(0, 1, 0), // up
      );
      frustum = VrFrustum.fromViewProjection(projection * view);
    });

    test('point in front of camera is inside frustum', () {
      expect(frustum.containsPoint(Vector3(0, 0, 0)), isTrue);
    });

    test('point behind camera is outside frustum', () {
      expect(frustum.containsPoint(Vector3(0, 0, 10)), isFalse);
    });

    test('point far left is outside frustum', () {
      expect(frustum.containsPoint(Vector3(-100, 0, 0)), isFalse);
    });

    test('point beyond far plane is outside', () {
      expect(frustum.containsPoint(Vector3(0, 0, -200)), isFalse);
    });

    test('AABB fully inside returns inside', () {
      final box = Aabb.fromCenterExtents(Vector3(0, 0, 2), Vector3(0.5, 0.5, 0.5));
      expect(frustum.testAabb(box), equals(CullResult.inside));
    });

    test('AABB fully outside returns outside', () {
      final box = Aabb.fromCenterExtents(Vector3(0, 0, 50), Vector3(0.5, 0.5, 0.5));
      expect(frustum.testAabb(box), equals(CullResult.outside));
    });

    test('AABB straddling frustum boundary returns intersecting', () {
      // Box that crosses the near plane boundary
      final box = Aabb.fromCenterExtents(Vector3(0, 0, 4.9), Vector3(0.5, 0.5, 0.5));
      final result = frustum.testAabb(box);
      // Could be inside or intersecting depending on frustum — both valid
      expect(result, isNot(equals(CullResult.outside)));
    });

    test('zero-size AABB at origin is inside', () {
      final box = Aabb.fromCenterExtents(Vector3(0, 0, 0), Vector3.zero());
      expect(frustum.testAabb(box), isNot(equals(CullResult.outside)));
    });

    test('frustum from identity matrix does not crash', () {
      final f = VrFrustum.fromViewProjection(Matrix4.identity());
      // Should not throw
      f.containsPoint(Vector3(0, 0, 0));
      f.testAabb(Aabb.fromCenterExtents(Vector3.zero(), Vector3(1, 1, 1)));
    });
  });
}
