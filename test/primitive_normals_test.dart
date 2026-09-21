import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('CylinderGeometry', () {
    test('caps and side own separate vertices with crisp explicit normals', () {
      final g = CylinderGeometry(radius: 0.5, height: 2, segments: 12);
      expect(g.vertexCount, 4 * 12 + 6);
      expect(g.normals.length, g.vertexCount);
      var capNormals = 0;
      var sideNormals = 0;
      for (var i = 0; i < g.vertexCount; i++) {
        final n = g.normals[i];
        expect(n.length, closeTo(1, 1e-6), reason: 'vertex $i');
        if (n.y.abs() > 0.999) {
          capNormals++;
        } else {
          // Side normals are exactly radial: no vertical component at all.
          expect(n.y, 0, reason: 'vertex $i is a tilted rim normal');
          final v = g.vertices[i];
          final radial = Vector3(v.x, 0, v.z).normalized();
          expect(n.dot(radial), closeTo(1, 1e-6), reason: 'vertex $i');
          sideNormals++;
        }
      }
      expect(capNormals, 2 * (12 + 2));
      expect(sideNormals, 2 * (12 + 1));
    });

    test('clamps degenerate segment counts', () {
      expect(CylinderGeometry(segments: 1).triangleCount, greaterThan(0));
    });
  });

  group('SphereGeometry', () {
    test('normals are exactly radial at any tessellation', () {
      for (final seg in [4, 8, 16, 32]) {
        final g = SphereGeometry(radius: 2, segments: seg);
        for (var i = 0; i < g.vertexCount; i++) {
          final n = g.normals[i];
          expect(n.length, closeTo(1, 1e-6));
          final v = g.vertices[i];
          if (v.length2 > 1e-12) {
            expect(n.dot(v.normalized()), closeTo(1, 1e-6), reason: '$seg/$i');
          }
        }
      }
    });
  });

  group('SharedPrimitives', () {
    test('fine variants exist for hero objects and are unit sized', () {
      expect(SharedPrimitives.unitSphereFine.vertexCount, 33 * 33);
      expect(SharedPrimitives.unitCylinderFine.vertexCount, 4 * 32 + 6);
      final box = SharedPrimitives.unitSphereFine.aabb;
      expect(box.max.x, closeTo(0.5, 1e-9));
      expect(box.min.y, closeTo(-0.5, 1e-9));
      final drum = SharedPrimitives.unitCylinderFine.aabb;
      expect(drum.max.y, closeTo(0.5, 1e-9));
      expect(drum.max.x, closeTo(0.5, 1e-9));
    });

    test('merged geometry keeps explicit normals under rotation', () {
      final merged = Geometry.merged([
        GeometryPlacement(
          SharedPrimitives.unitCylinder,
          Matrix4.compose(
            Vector3.zero(),
            Quaternion.axisAngle(Vector3(0, 0, 1), pi / 2),
            Vector3(1, 3, 1),
          ),
        ),
      ]);
      // After rotating Y onto -X, cap normals point along ±X.
      final caps = merged.normals.where((n) => n.x.abs() > 0.999).length;
      expect(caps, 2 * (16 + 2));
      for (final n in merged.normals) {
        expect(n.length, closeTo(1, 1e-6));
      }
    });
  });
}
