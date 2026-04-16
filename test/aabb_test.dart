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
  });
}
