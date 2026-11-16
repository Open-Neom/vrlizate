import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('Aabb', () {
    test('default constructor has inverted min/max (empty box)', () {
      final box = Aabb();
      expect(box.min.x, double.infinity);
      expect(box.max.x, double.negativeInfinity);
    });

    test('expandToInclude builds correct bounds', () {
      final box = Aabb();
      box.expandToInclude(Vector3(-1, -2, -3));
      box.expandToInclude(Vector3(4, 5, 6));

      expect(box.min.x, closeTo(-1, 1e-6));
      expect(box.max.y, closeTo(5, 1e-6));
      expect(box.center.x, closeTo(1.5, 1e-6));
    });

    test('containsPoint inside returns true', () {
      final box = Aabb.fromCenterExtents(Vector3.zero(), Vector3(1, 1, 1));
      expect(box.containsPoint(Vector3(0, 0, 0)), isTrue);
      expect(box.containsPoint(Vector3(0.9, 0.9, 0.9)), isTrue);
    });

    test('containsPoint outside returns false', () {
      final box = Aabb.fromCenterExtents(Vector3.zero(), Vector3(1, 1, 1));
      expect(box.containsPoint(Vector3(2, 0, 0)), isFalse);
    });

    test('containsPoint on boundary returns true', () {
      final box = Aabb.fromCenterExtents(Vector3.zero(), Vector3(1, 1, 1));
      expect(box.containsPoint(Vector3(1, 1, 1)), isTrue);
    });

    test('intersectsAabb detects overlap', () {
      final a = Aabb.fromCenterExtents(Vector3.zero(), Vector3(1, 1, 1));
      final b = Aabb.fromCenterExtents(Vector3(1.5, 0, 0), Vector3(1, 1, 1));
      expect(a.intersectsAabb(b), isTrue);
    });

    test('intersectsAabb rejects non-overlap', () {
      final a = Aabb.fromCenterExtents(Vector3.zero(), Vector3(1, 1, 1));
      final b = Aabb.fromCenterExtents(Vector3(5, 0, 0), Vector3(1, 1, 1));
      expect(a.intersectsAabb(b), isFalse);
    });

    test('transformed produces enclosing box', () {
      final box = Aabb.fromCenterExtents(Vector3.zero(), Vector3(1, 1, 1));
      final rotation = Matrix4.rotationZ(pi / 4); // 45 degrees

      final transformed = box.transformed(rotation);

      // Rotated box should be larger (diagonal)
      expect(transformed.size.x, greaterThan(box.size.x));
    });

    test('expandToIncludeAabb merges two boxes', () {
      final a = Aabb.fromCenterExtents(Vector3(-5, 0, 0), Vector3(1, 1, 1));
      final b = Aabb.fromCenterExtents(Vector3(5, 0, 0), Vector3(1, 1, 1));
      a.expandToIncludeAabb(b);

      expect(a.min.x, closeTo(-6, 1e-6));
      expect(a.max.x, closeTo(6, 1e-6));
    });

    test(
      'transformAffineInto and expandBoundsInPlace match 8-corner transformed across rotation/scale/translation',
      () {
        final box = Aabb(
          min: Vector3(-1.25, 0.4, -3.5),
          max: Vector3(2.75, 4.1, 0.8),
        );
        final matrix = Matrix4.compose(
          Vector3(12.5, -3.2, 8.75),
          Quaternion.euler(0.62, -1.14, 0.37),
          Vector3(1.8, -0.75, 2.4),
        );
        final expected = box.transformed(matrix);
        final out = Aabb();
        box.transformAffineInto(matrix, out);

        expect(out.min.x, closeTo(expected.min.x, 1e-9));
        expect(out.min.y, closeTo(expected.min.y, 1e-9));
        expect(out.min.z, closeTo(expected.min.z, 1e-9));
        expect(out.max.x, closeTo(expected.max.x, 1e-9));
        expect(out.max.y, closeTo(expected.max.y, 1e-9));
        expect(out.max.z, closeTo(expected.max.z, 1e-9));

        final merged = Aabb(
          min: Vector3(-20, 0, 0),
          max: Vector3(-19, 1, 1),
        )..expandBoundsInPlace(out);
        expect(merged.min.x, closeTo(-20, 1e-9));
        expect(merged.max.x, closeTo(expected.max.x, 1e-9));
        expect(merged.max.z, closeTo(expected.max.z, 1e-9));
      },
    );
  });
}
