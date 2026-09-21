import 'dart:math';

import 'package:vector_math/vector_math.dart';

import '../geometry.dart';

/// Closed cylinder along Y, centered on the origin, wound counter-clockwise
/// from outside like [CubeGeometry] so back-face culling keeps the near side.
///
/// Caps and side own separate vertices with explicit normals — ±Y on the
/// caps, radial on the side — so the rim is a crisp edge. Sharing the rim
/// vertices (the previous layout) averaged cap and side normals to a 45°
/// tilt, which rendered every column, post and torch handle with a puffy,
/// rounded rim and let the cap's shading bleed down the side.
///
/// Layout: bottom cap (center + seg+1 ring), top cap (center + seg+1 ring),
/// side (2 × (seg+1) ring vertices). Vertex count `4·seg + 6`.
class CylinderGeometry extends Geometry {
  CylinderGeometry({
    double radius = 0.5,
    double height = 1.0,
    int segments = 16,
  }) : this._(radius, height, max(3, segments));

  CylinderGeometry._(double radius, double height, int segments)
    : super(
        vertices: _buildVertices(radius, height, segments),
        normals: _buildNormals(segments),
        uvs: _buildUvs(segments),
        indices: _buildIndices(segments),
      );

  static List<Vector3> _buildVertices(double r, double h, int seg) {
    final verts = <Vector3>[];
    final halfH = h / 2;
    for (final y in [-halfH, halfH]) {
      verts.add(Vector3(0, y, 0));
      for (var i = 0; i <= seg; i++) {
        final theta = 2 * pi * i / seg;
        verts.add(Vector3(r * cos(theta), y, r * sin(theta)));
      }
    }
    for (final y in [-halfH, halfH]) {
      for (var i = 0; i <= seg; i++) {
        final theta = 2 * pi * i / seg;
        verts.add(Vector3(r * cos(theta), y, r * sin(theta)));
      }
    }
    return verts;
  }

  static List<Vector3> _buildNormals(int seg) {
    final normals = <Vector3>[];
    for (final ny in [-1.0, 1.0]) {
      for (var i = 0; i <= seg + 1; i++) {
        normals.add(Vector3(0, ny, 0));
      }
    }
    for (var ring = 0; ring < 2; ring++) {
      for (var i = 0; i <= seg; i++) {
        final theta = 2 * pi * i / seg;
        normals.add(Vector3(cos(theta), 0, sin(theta)));
      }
    }
    return normals;
  }

  static List<Vector2> _buildUvs(int seg) {
    final uvs = <Vector2>[];
    for (var cap = 0; cap < 2; cap++) {
      uvs.add(Vector2(0.5, 0.5));
      for (var i = 0; i <= seg; i++) {
        final theta = 2 * pi * i / seg;
        uvs.add(Vector2(0.5 + 0.5 * cos(theta), 0.5 + 0.5 * sin(theta)));
      }
    }
    for (final v in [1.0, 0.0]) {
      for (var i = 0; i <= seg; i++) {
        uvs.add(Vector2(i / seg, v));
      }
    }
    return uvs;
  }

  static List<int> _buildIndices(int seg) {
    final idx = <int>[];
    const bottomCenter = 0;
    final topCenter = seg + 2;
    // Counter-clockwise seen from outside (the glTF/flutter_scene front face
    // and what the Canvas rasterizer culls against), like CubeGeometry.
    for (var i = 0; i < seg; i++) {
      idx.addAll([bottomCenter, bottomCenter + i + 1, bottomCenter + i + 2]);
    }
    for (var i = 0; i < seg; i++) {
      idx.addAll([topCenter, topCenter + i + 2, topCenter + i + 1]);
    }
    final sideBottom = 2 * (seg + 2);
    final sideTop = sideBottom + seg + 1;
    for (var i = 0; i < seg; i++) {
      final b0 = sideBottom + i;
      final b1 = sideBottom + i + 1;
      final t0 = sideTop + i;
      final t1 = sideTop + i + 1;
      idx.addAll([b0, t1, b1, b0, t0, t1]);
    }
    return idx;
  }
}
