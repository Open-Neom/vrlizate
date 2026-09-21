import 'dart:math';

import 'package:vector_math/vector_math.dart';

import '../geometry.dart';

/// UV sphere centered on the origin with analytic (exactly radial) normals,
/// so shading is smooth at any tessellation instead of showing the faceting
/// that averaged face normals leave on a coarse mesh.
class SphereGeometry extends Geometry {
  SphereGeometry({double radius = 0.5, int segments = 16})
    : this._(radius, max(3, segments));

  SphereGeometry._(double radius, int segments)
    : super(
        vertices: _buildVertices(radius, segments),
        normals: _buildNormals(segments),
        uvs: _buildUvs(segments),
        indices: _buildIndices(segments),
      );

  static List<Vector3> _buildNormals(int seg) {
    final normals = <Vector3>[];
    for (var y = 0; y <= seg; y++) {
      final phi = pi * y / seg;
      for (var x = 0; x <= seg; x++) {
        final theta = 2 * pi * x / seg;
        normals.add(
          Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)),
        );
      }
    }
    return normals;
  }

  static List<Vector3> _buildVertices(double r, int seg) {
    final verts = <Vector3>[];
    for (var y = 0; y <= seg; y++) {
      final phi = pi * y / seg;
      for (var x = 0; x <= seg; x++) {
        final theta = 2 * pi * x / seg;
        verts.add(
          Vector3(
            r * sin(phi) * cos(theta),
            r * cos(phi),
            r * sin(phi) * sin(theta),
          ),
        );
      }
    }
    return verts;
  }

  static List<Vector2> _buildUvs(int seg) {
    final uvs = <Vector2>[];
    for (var y = 0; y <= seg; y++) {
      for (var x = 0; x <= seg; x++) {
        uvs.add(Vector2(x / seg, y / seg));
      }
    }
    return uvs;
  }

  static List<int> _buildIndices(int seg) {
    final idx = <int>[];
    for (var y = 0; y < seg; y++) {
      for (var x = 0; x < seg; x++) {
        final a = y * (seg + 1) + x;
        final b = a + seg + 1;
        // Counter-clockwise from outside, like CubeGeometry: the previous
        // order wound every face inward, so back-face culling drew spheres
        // inside-out (near side culled, far interior shown, lighting
        // mirrored) on both the Canvas and the GPU renderers.
        idx.addAll([a, a + 1, b, b, a + 1, b + 1]);
      }
    }
    return idx;
  }
}
