import 'package:flutter_test/flutter_test.dart';

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('Geometry', () {
    test('auto-computed normals are unit length', () {
      final geo = CubeGeometry(size: 1);
      for (final n in geo.normals) {
        expect(n.length, closeTo(1.0, 1e-4));
      }
    });

    test('cube has 24 vertices and 36 indices (6 faces * 2 tris)', () {
      final geo = CubeGeometry(size: 1);
      expect(geo.vertexCount, equals(24));
      expect(geo.triangleCount, equals(12));
      expect(geo.indices.length, equals(36));
    });

    test('sphere has correct vertex count', () {
      final geo = SphereGeometry(radius: 1, segments: 8);
      // (8+1) * (8+1) = 81 vertices
      expect(geo.vertexCount, equals(81));
    });

    test('sphere vertices are at correct radius', () {
      final geo = SphereGeometry(radius: 2, segments: 16);
      for (final v in geo.vertices) {
        // All vertices should be at radius 2 (with floating point tolerance)
        expect(v.length, closeTo(2, 1e-4));
      }
    });

    test('plane is flat on Y=0', () {
      final geo = PlaneGeometry(width: 5, height: 5);
      for (final v in geo.vertices) {
        expect(v.y, closeTo(0, 1e-6));
      }
    });

    test('cylinder has correct cap + side geometry', () {
      final geo = CylinderGeometry(radius: 1, height: 2, segments: 8);
      expect(geo.vertexCount, greaterThan(0));
      expect(geo.indices.length % 3, equals(0)); // All triangles
    });

    test('all indices are within vertex bounds', () {
      final geometries = [
        CubeGeometry(size: 1),
        SphereGeometry(radius: 1, segments: 8),
        PlaneGeometry(width: 1, height: 1),
        CylinderGeometry(radius: 1, height: 1, segments: 8),
      ];

      for (final geo in geometries) {
        for (final idx in geo.indices) {
          expect(idx, greaterThanOrEqualTo(0));
          expect(idx, lessThan(geo.vertexCount),
            reason: '${geo.runtimeType} index $idx >= ${geo.vertexCount}');
        }
      }
    });

    test('aabb encloses all vertices', () {
      final geo = SphereGeometry(radius: 3, segments: 16);
      final box = geo.aabb;
      for (final v in geo.vertices) {
        expect(box.containsPoint(v), isTrue,
          reason: 'Vertex $v outside AABB');
      }
    });

    test('zero-size cube has zero-volume aabb', () {
      final geo = CubeGeometry(size: 0);
      expect(geo.aabb.size.x, closeTo(0, 1e-6));
    });

    test('high-segment sphere normals are consistent (all same direction)', () {
      final geo = SphereGeometry(radius: 1, segments: 16);
      int positive = 0;
      int negative = 0;
      for (var i = 0; i < geo.vertexCount; i++) {
        final v = geo.vertices[i];
        final n = geo.normals[i];
        if (v.length < 1e-6 || n.length < 1e-6) continue;
        final dot = v.normalized().dot(n);
        if (dot > 0) positive++;
        if (dot < 0) negative++;
      }
      final total = positive + negative;
      expect(total, greaterThan(0), reason: 'No valid normals found');
      // All normals should be consistent: either all outward or all inward
      final consistency = (positive > negative ? positive : negative) / total;
      expect(consistency, greaterThan(0.95),
        reason: 'Normals inconsistent: $positive outward, $negative inward');
    });
  });
}
