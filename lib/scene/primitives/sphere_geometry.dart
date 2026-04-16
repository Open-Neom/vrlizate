import 'dart:math';

import 'package:vector_math/vector_math.dart';

import '../geometry.dart';

class SphereGeometry extends Geometry {
  SphereGeometry({double radius = 0.5, int segments = 16})
    : super(
        vertices: _buildVertices(radius, segments),
        uvs: _buildUvs(segments),
        indices: _buildIndices(segments),
      );

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
        idx.addAll([a, b, a + 1, b, b + 1, a + 1]);
      }
    }
    return idx;
  }
}
