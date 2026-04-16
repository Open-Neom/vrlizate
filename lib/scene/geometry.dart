import 'package:vector_math/vector_math.dart';

import '../core/math/aabb.dart';

/// Raw vertex data for a 3D geometry.
class Geometry {
  /// Vertex positions (3 floats per vertex).
  final List<Vector3> vertices;

  /// Vertex normals (3 floats per vertex).
  final List<Vector3> normals;

  /// UV coordinates (2 floats per vertex).
  final List<Vector2> uvs;

  /// Triangle indices (3 per triangle).
  final List<int> indices;

  Aabb? _cachedAabb;

  Geometry({
    required this.vertices,
    List<Vector3>? normals,
    List<Vector2>? uvs,
    required this.indices,
  }) : normals = normals ?? _computeNormals(vertices, indices),
       uvs = uvs ?? List.filled(vertices.length, Vector2.zero());

  int get vertexCount => vertices.length;
  int get triangleCount => indices.length ~/ 3;

  Aabb get aabb {
    if (_cachedAabb != null) return _cachedAabb!;
    final box = Aabb();
    for (final v in vertices) {
      box.expandToInclude(v);
    }
    _cachedAabb = box;
    return box;
  }

  /// Computes face normals and averages them per vertex.
  static List<Vector3> _computeNormals(
    List<Vector3> vertices,
    List<int> indices,
  ) {
    final normals = List.generate(vertices.length, (_) => Vector3.zero());

    for (var i = 0; i < indices.length; i += 3) {
      final a = vertices[indices[i]];
      final b = vertices[indices[i + 1]];
      final c = vertices[indices[i + 2]];

      final edge1 = b - a;
      final edge2 = c - a;
      final faceNormal = edge1.cross(edge2)..normalize();

      normals[indices[i]] += faceNormal;
      normals[indices[i + 1]] += faceNormal;
      normals[indices[i + 2]] += faceNormal;
    }

    for (final n in normals) {
      if (n.length > 0) n.normalize();
    }

    return normals;
  }
}
