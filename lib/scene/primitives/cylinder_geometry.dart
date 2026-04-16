import 'dart:math';

import 'package:vector_math/vector_math.dart';

import '../geometry.dart';

class CylinderGeometry extends Geometry {
  CylinderGeometry({
    double radius = 0.5,
    double height = 1.0,
    int segments = 16,
  }) : super(
         vertices: _buildVertices(radius, height, segments),
         indices: _buildIndices(segments),
       );

  static List<Vector3> _buildVertices(double r, double h, int seg) {
    final verts = <Vector3>[];
    final halfH = h / 2;

    // Bottom center
    verts.add(Vector3(0, -halfH, 0));
    // Bottom ring
    for (var i = 0; i <= seg; i++) {
      final theta = 2 * pi * i / seg;
      verts.add(Vector3(r * cos(theta), -halfH, r * sin(theta)));
    }

    // Top center
    verts.add(Vector3(0, halfH, 0));
    // Top ring
    for (var i = 0; i <= seg; i++) {
      final theta = 2 * pi * i / seg;
      verts.add(Vector3(r * cos(theta), halfH, r * sin(theta)));
    }

    return verts;
  }

  static List<int> _buildIndices(int seg) {
    final idx = <int>[];
    const bottomCenter = 0;
    final topCenter = seg + 2;

    // Bottom cap
    for (var i = 0; i < seg; i++) {
      idx.addAll([bottomCenter, i + 2, i + 1]);
    }

    // Top cap
    for (var i = 0; i < seg; i++) {
      idx.addAll([topCenter, topCenter + i + 1, topCenter + i + 2]);
    }

    // Side faces
    for (var i = 0; i < seg; i++) {
      final b0 = i + 1;
      final b1 = i + 2;
      final t0 = topCenter + i + 1;
      final t1 = topCenter + i + 2;
      idx.addAll([b0, b1, t1, b0, t1, t0]);
    }

    return idx;
  }
}
