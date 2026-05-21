import 'package:flutter_test/flutter_test.dart';

import 'package:vrlizate/vrlizate.dart';

/// Geometry generation benchmarks — verifies that primitive generation
/// at high polygon counts is fast and produces correct topology.
void main() {
  group('Geometry — Stress', () {
    test('high-poly sphere (128 segments) generates in < 100ms', () {
      final sw = Stopwatch()..start();
      final geo = SphereGeometry(radius: 1, segments: 128);
      sw.stop();

      const expectedVerts = (128 + 1) * (128 + 1);
      expect(geo.vertexCount, equals(expectedVerts));
      expect(geo.normals.length, equals(expectedVerts));
      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('high-poly sphere (256 segments) vertex count', () {
      final geo = SphereGeometry(radius: 1, segments: 256);
      expect(geo.vertexCount, equals(257 * 257));
      expect(geo.indices.length, equals(256 * 256 * 6));
    });

    test('cube has exactly 24 vertices and 36 indices', () {
      final geo = CubeGeometry(size: 1);
      expect(geo.vertexCount, equals(24));
      expect(geo.indices.length, equals(36));
    });

    test('plane has 4 vertices and 6 indices', () {
      final geo = PlaneGeometry(width: 1, height: 1);
      expect(geo.vertexCount, equals(4));
      expect(geo.indices.length, equals(6));
    });

    test('cylinder has correct topology', () {
      final geo = CylinderGeometry(radius: 1, height: 2, segments: 32);
      expect(geo.vertexCount, greaterThan(60));
      expect(geo.indices.length, greaterThan(180));
    });

    test('AABB of unit sphere contains all vertices', () {
      final geo = SphereGeometry(radius: 1, segments: 32);
      final aabb = geo.aabb;

      for (final v in geo.vertices) {
        expect(aabb.containsPoint(v), isTrue,
          reason: 'Vertex $v outside AABB');
      }
    });

    test('AABB of unit cube is exactly [-0.5, 0.5]^3', () {
      final geo = CubeGeometry(size: 1);
      final aabb = geo.aabb;

      expect(aabb.min.x, closeTo(-0.5, 1e-6));
      expect(aabb.max.x, closeTo(0.5, 1e-6));
      expect(aabb.min.y, closeTo(-0.5, 1e-6));
      expect(aabb.max.y, closeTo(0.5, 1e-6));
    });

    test('all indices are within vertex range', () {
      final geometries = [
        SphereGeometry(radius: 1, segments: 16),
        CubeGeometry(size: 1),
        PlaneGeometry(width: 1, height: 1),
        CylinderGeometry(radius: 0.5, height: 1, segments: 16),
      ];

      for (final geo in geometries) {
        for (final idx in geo.indices) {
          expect(idx, lessThan(geo.vertexCount),
            reason: 'Index $idx out of range for ${geo.runtimeType}');
          expect(idx, greaterThanOrEqualTo(0));
        }
      }
    });

    test('normal computation batch: 10 spheres x 64 segments < 200ms', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        SphereGeometry(radius: 1, segments: 64);
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(200));
    });
  });
}
