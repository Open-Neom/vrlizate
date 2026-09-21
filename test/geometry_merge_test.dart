import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('SharedPrimitives', () {
    test('returns the same instance on every access', () {
      expect(
        identical(SharedPrimitives.unitCube, SharedPrimitives.unitCube),
        isTrue,
      );
      expect(
        identical(SharedPrimitives.unitSphere, SharedPrimitives.unitSphere),
        isTrue,
      );
      expect(
        identical(SharedPrimitives.unitCylinder, SharedPrimitives.unitCylinder),
        isTrue,
      );
    });

    test('unit primitives span exactly one meter', () {
      for (final geometry in [
        SharedPrimitives.unitCube,
        SharedPrimitives.unitSphere,
        SharedPrimitives.unitCylinder,
      ]) {
        final box = geometry.aabb;
        expect(box.max.x - box.min.x, closeTo(1.0, 1e-9));
        expect(box.max.y - box.min.y, closeTo(1.0, 1e-9));
      }
      final plane = SharedPrimitives.unitPlane.aabb;
      expect(plane.max.x - plane.min.x, closeTo(1.0, 1e-9));
      expect(plane.max.z - plane.min.z, closeTo(1.0, 1e-9));
    });
  });

  group('Geometry.merged', () {
    test('concatenates vertices and offsets indices', () {
      final cube = SharedPrimitives.unitCube;
      final merged = Geometry.merged([
        GeometryPlacement.box(
          cube,
          position: Vector3(-2, 0, 0),
          scale: Vector3.all(1),
        ),
        GeometryPlacement.box(
          cube,
          position: Vector3(2, 0, 0),
          scale: Vector3.all(1),
        ),
      ]);
      expect(merged.vertexCount, cube.vertexCount * 2);
      expect(merged.indices.length, cube.indices.length * 2);
      expect(merged.triangleCount, cube.triangleCount * 2);
      expect(merged.indices.reduce(max), merged.vertexCount - 1);
      expect(merged.indices.reduce(min), 0);
      // Second copy's indices all point into the second vertex block.
      final second = merged.indices.sublist(cube.indices.length);
      expect(second.every((i) => i >= cube.vertexCount), isTrue);
    });

    test('bakes translation and non-uniform scale into positions and AABB', () {
      final merged = Geometry.merged([
        GeometryPlacement.box(
          SharedPrimitives.unitCube,
          position: Vector3(0, 2.25, -16),
          scale: Vector3(32, 4.5, 0.6),
        ),
      ]);
      // vector_math stores Vector3 as Float32; compare at metric precision.
      final box = merged.aabb;
      expect(box.min.x, closeTo(-16, 1e-5));
      expect(box.max.x, closeTo(16, 1e-5));
      expect(box.min.y, closeTo(0, 1e-5));
      expect(box.max.y, closeTo(4.5, 1e-5));
      expect(box.min.z, closeTo(-16.3, 1e-5));
      expect(box.max.z, closeTo(-15.7, 1e-5));
    });

    test('normals use the inverse-transpose and stay unit length', () {
      // A cube stretched 10× along X: side normals must remain exactly ±X,
      // and top/bottom ±Y — a naive matrix multiply would skew and scale them.
      final merged = Geometry.merged([
        GeometryPlacement.box(
          SharedPrimitives.unitCube,
          position: Vector3.zero(),
          scale: Vector3(10, 1, 1),
        ),
      ]);
      for (final n in merged.normals) {
        expect(n.length, closeTo(1.0, 1e-9));
        final axisAligned =
            (n.x.abs() > 0.999) || (n.y.abs() > 0.999) || (n.z.abs() > 0.999);
        expect(axisAligned, isTrue, reason: 'normal $n');
      }
    });

    test('rotation keeps outward normals outward', () {
      final rotation = Matrix4.rotationY(pi / 3);
      final merged = Geometry.merged([
        GeometryPlacement(SharedPrimitives.unitCube, rotation),
      ]);
      // For a convex solid centered on the origin, every vertex normal must
      // point away from the center.
      for (var i = 0; i < merged.vertexCount; i++) {
        expect(merged.normals[i].dot(merged.vertices[i]), greaterThan(0));
      }
    });

    test('mirroring transforms flip winding so faces stay front-facing', () {
      final mirror = Matrix4.diagonal3Values(-1, 1, 1);
      final merged = Geometry.merged([
        GeometryPlacement(SharedPrimitives.unitCube, mirror),
      ]);
      // Recompute face normals from the winding and compare with the baked
      // (inverse-transpose) vertex normals: they must agree in direction.
      for (var i = 0; i < merged.indices.length; i += 3) {
        final a = merged.vertices[merged.indices[i]];
        final b = merged.vertices[merged.indices[i + 1]];
        final c = merged.vertices[merged.indices[i + 2]];
        final face = (b - a).cross(c - a)..normalize();
        expect(face.dot(merged.normals[merged.indices[i]]), greaterThan(0.99));
      }
    });

    test('rejects empty input and degenerate transforms', () {
      expect(() => Geometry.merged(const []), throwsArgumentError);
      expect(
        () => Geometry.merged([
          GeometryPlacement.box(
            SharedPrimitives.unitCube,
            position: Vector3.zero(),
            scale: Vector3(1, 0, 1),
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('does not mutate the shared source primitive', () {
      final cube = SharedPrimitives.unitCube;
      final before = cube.vertices.map((v) => v.clone()).toList();
      Geometry.merged([
        GeometryPlacement.box(
          cube,
          position: Vector3(5, 5, 5),
          scale: Vector3(3, 3, 3),
        ),
      ]);
      for (var i = 0; i < before.length; i++) {
        expect(cube.vertices[i], before[i]);
      }
    });
  });
}
