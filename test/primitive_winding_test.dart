import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

/// Fraction of triangles whose counter-clockwise normal agrees with
/// [outward] at their centroid. 1.0 means every face is a front face when
/// seen from outside — what both renderers cull against.
double outwardFraction(Geometry g, Vector3 Function(Vector3 centroid) outward) {
  var agree = 0, total = 0;
  for (var i = 0; i < g.indices.length; i += 3) {
    final a = g.vertices[g.indices[i]];
    final b = g.vertices[g.indices[i + 1]];
    final c = g.vertices[g.indices[i + 2]];
    final n = (b - a).cross(c - a);
    if (n.length2 < 1e-12) continue;
    final o = outward((a + b + c) / 3);
    if (o.length2 < 1e-12) continue;
    total++;
    if (n.dot(o) > 0) agree++;
  }
  return total == 0 ? 0 : agree / total;
}

void main() {
  group('primitive winding is counter-clockwise from outside', () {
    test('cube and plane (the reference)', () {
      expect(outwardFraction(CubeGeometry(size: 1), (c) => c), 1.0);
      expect(
        outwardFraction(
          PlaneGeometry(width: 1, height: 1),
          (_) => Vector3(0, 1, 0),
        ),
        1.0,
      );
    });

    test('sphere', () {
      for (final seg in [3, 8, 16, 32]) {
        expect(
          outwardFraction(SphereGeometry(radius: 1, segments: seg), (c) => c),
          1.0,
          reason: '$seg segments',
        );
      }
    });

    test('cylinder side and caps', () {
      for (final seg in [3, 8, 16, 32]) {
        final cyl = CylinderGeometry(radius: 1, height: 1, segments: seg);
        expect(
          outwardFraction(
            cyl,
            (c) => c.y.abs() < 0.49 ? Vector3(c.x, 0, c.z) : Vector3.zero(),
          ),
          1.0,
          reason: 'side, $seg segments',
        );
        expect(
          outwardFraction(
            cyl,
            (c) => c.y.abs() > 0.49 ? Vector3(0, c.y, 0) : Vector3.zero(),
          ),
          1.0,
          reason: 'caps, $seg segments',
        );
      }
    });

    test('explicit normals agree with the face winding', () {
      for (final g in [
        SphereGeometry(radius: 1, segments: 12),
        CylinderGeometry(radius: 1, height: 2, segments: 12),
      ]) {
        for (var i = 0; i < g.indices.length; i += 3) {
          final ia = g.indices[i], ib = g.indices[i + 1], ic = g.indices[i + 2];
          final face = (g.vertices[ib] - g.vertices[ia]).cross(
            g.vertices[ic] - g.vertices[ia],
          );
          if (face.length2 < 1e-12) continue;
          final shading = g.normals[ia] + g.normals[ib] + g.normals[ic];
          expect(face.dot(shading), greaterThan(0), reason: 'triangle $i');
        }
      }
    });

    test('shared primitives are all outward', () {
      for (final (name, g) in [
        ('unitSphere', SharedPrimitives.unitSphere),
        ('unitSphereCoarse', SharedPrimitives.unitSphereCoarse),
        ('unitSphereFine', SharedPrimitives.unitSphereFine),
      ]) {
        expect(outwardFraction(g, (c) => c), 1.0, reason: name);
      }
      for (final (name, g) in [
        ('unitCylinder', SharedPrimitives.unitCylinder),
        ('unitCylinderCoarse', SharedPrimitives.unitCylinderCoarse),
        ('unitCylinderFine', SharedPrimitives.unitCylinderFine),
      ]) {
        expect(
          outwardFraction(
            g,
            (c) => c.y.abs() < 0.49 ? Vector3(c.x, 0, c.z) : Vector3(0, c.y, 0),
          ),
          1.0,
          reason: name,
        );
      }
    });
  });
}
