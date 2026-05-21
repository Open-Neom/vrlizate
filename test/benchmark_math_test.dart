import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

/// Math and transform benchmarks — validates correctness and speed of the
/// core math layer: transforms, quaternions, matrix chains, frustum culling.
void main() {
  group('Transform3D — Correctness', () {
    test('position sets translation in localMatrix', () {
      final t = Transform3D();
      t.position = Vector3(3, 4, 5);

      final translation = t.localMatrix.getTranslation();
      expect(translation.x, closeTo(3, 1e-6));
      expect(translation.y, closeTo(4, 1e-6));
      expect(translation.z, closeTo(5, 1e-6));
    });

    test('scale is applied correctly', () {
      final t = Transform3D();
      t.scale = Vector3(2, 3, 4);
      t.position = Vector3.zero();

      final m = t.localMatrix;
      final scaled = m.transformed3(Vector3(1, 1, 1));
      expect(scaled.x, closeTo(2, 1e-3));
      expect(scaled.y, closeTo(3, 1e-3));
      expect(scaled.z, closeTo(4, 1e-3));
    });

    test('quaternion rotation avoids gimbal lock at 90 pitch', () {
      final t = Transform3D();
      t.rotation = Quaternion.euler(0, pi / 2, 0);

      final forward = t.forward;
      expect(forward.length, closeTo(1, 1e-3));
    });

    test('lookAt produces correct forward direction', () {
      final t = Transform3D();
      t.position = Vector3(0, 0, 5);
      t.lookAt(Vector3(0, 0, 0));

      final forward = t.forward;
      expect(forward.z, lessThan(0));
    });
  });

  group('Transform3D — Performance', () {
    test('10,000 localMatrix computations < 50ms', () {
      final transforms = List.generate(10000, (i) {
        final t = Transform3D();
        t.position = Vector3(i.toDouble(), 0, 0);
        t.rotation = Quaternion.euler(i * 0.01, i * 0.02, 0);
        t.scale = Vector3.all(1 + i * 0.001);
        return t;
      });

      final sw = Stopwatch()..start();
      for (final t in transforms) {
        t.localMatrix;
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  group('VrFrustum — Performance', () {
    test('frustum cull 10,000 AABBs < 50ms', () {
      final vp =
          makePerspectiveMatrix(pi / 3, 16 / 9, 0.1, 100) *
          makeViewMatrix(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
      final frustum = VrFrustum.fromViewProjection(vp);

      final boxes = List.generate(10000, (i) {
        return Aabb.fromCenterExtents(
          Vector3((i % 100).toDouble() - 50, (i ~/ 100).toDouble() - 50, 0),
          Vector3(0.5, 0.5, 0.5),
        );
      });

      final sw = Stopwatch()..start();
      int inside = 0;
      for (final box in boxes) {
        if (frustum.testAabb(box) != CullResult.outside) inside++;
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(50));
      expect(inside, greaterThan(0));
      expect(inside, lessThan(10000));
    });
  });

  group('AABB — Performance', () {
    test('100,000 point expansions < 100ms', () {
      final aabb = Aabb();
      final rng = Random(42);

      final sw = Stopwatch()..start();
      for (var i = 0; i < 100000; i++) {
        aabb.expandToInclude(
          Vector3(
            rng.nextDouble() * 200 - 100,
            rng.nextDouble() * 200 - 100,
            rng.nextDouble() * 200 - 100,
          ),
        );
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(100));
      expect(aabb.min.x, lessThan(-90));
      expect(aabb.max.x, greaterThan(90));
    });

    test('10,000 AABB intersection checks < 20ms', () {
      final a = Aabb.fromCenterExtents(Vector3.zero(), Vector3(5, 5, 5));
      final boxes = List.generate(10000, (i) {
        return Aabb.fromCenterExtents(
          Vector3((i % 100).toDouble() - 50, (i ~/ 100).toDouble() - 50, 0),
          Vector3(0.5, 0.5, 0.5),
        );
      });

      final sw = Stopwatch()..start();
      int hits = 0;
      for (final b in boxes) {
        if (a.intersectsAabb(b)) hits++;
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(20));
      expect(hits, greaterThan(0));
    });
  });
}
