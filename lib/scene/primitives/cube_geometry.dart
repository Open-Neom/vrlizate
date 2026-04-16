import 'package:vector_math/vector_math.dart';

import '../geometry.dart';

class CubeGeometry extends Geometry {
  CubeGeometry({double size = 1.0})
    : super(vertices: _buildVertices(size), indices: _buildIndices());

  static List<Vector3> _buildVertices(double s) {
    final h = s / 2;
    return [
      // Front
      Vector3(-h, -h, h),
      Vector3(h, -h, h),
      Vector3(h, h, h),
      Vector3(-h, h, h),
      // Back
      Vector3(h, -h, -h),
      Vector3(-h, -h, -h),
      Vector3(-h, h, -h),
      Vector3(h, h, -h),
      // Top
      Vector3(-h, h, h),
      Vector3(h, h, h),
      Vector3(h, h, -h),
      Vector3(-h, h, -h),
      // Bottom
      Vector3(-h, -h, -h),
      Vector3(h, -h, -h),
      Vector3(h, -h, h),
      Vector3(-h, -h, h),
      // Right
      Vector3(h, -h, h),
      Vector3(h, -h, -h),
      Vector3(h, h, -h),
      Vector3(h, h, h),
      // Left
      Vector3(-h, -h, -h),
      Vector3(-h, -h, h),
      Vector3(-h, h, h),
      Vector3(-h, h, -h),
    ];
  }

  static List<int> _buildIndices() {
    final idx = <int>[];
    for (var face = 0; face < 6; face++) {
      final o = face * 4;
      idx.addAll([o, o + 1, o + 2, o, o + 2, o + 3]);
    }
    return idx;
  }
}
