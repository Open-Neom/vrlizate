import 'package:vector_math/vector_math.dart';

import '../geometry.dart';

class PlaneGeometry extends Geometry {
  PlaneGeometry({
    double width = 1.0,
    double height = 1.0,
    int segW = 1,
    int segH = 1,
  }) : super(
         vertices: _buildVertices(width, height, segW, segH),
         uvs: _buildUvs(segW, segH),
         indices: _buildIndices(segW, segH),
       );

  static List<Vector3> _buildVertices(double w, double h, int sw, int sh) {
    final verts = <Vector3>[];
    for (var y = 0; y <= sh; y++) {
      for (var x = 0; x <= sw; x++) {
        verts.add(Vector3((x / sw - 0.5) * w, 0, (y / sh - 0.5) * h));
      }
    }
    return verts;
  }

  static List<Vector2> _buildUvs(int sw, int sh) {
    final uvs = <Vector2>[];
    for (var y = 0; y <= sh; y++) {
      for (var x = 0; x <= sw; x++) {
        uvs.add(Vector2(x / sw, y / sh));
      }
    }
    return uvs;
  }

  static List<int> _buildIndices(int sw, int sh) {
    final idx = <int>[];
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        final a = y * (sw + 1) + x;
        final b = a + sw + 1;
        idx.addAll([a, b, a + 1, b, b + 1, a + 1]);
      }
    }
    return idx;
  }
}
