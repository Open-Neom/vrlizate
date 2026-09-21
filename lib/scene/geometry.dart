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

  /// Bakes several placed geometries into one static geometry.
  ///
  /// Each [GeometryPlacement] contributes its vertices transformed by its
  /// matrix (normals by the inverse-transpose, renormalized), its UVs
  /// unchanged and its indices offset. Use it for static scenery that shares
  /// one material — a run of wall blocks, a tiled floor, the grout lines of a
  /// plaza — so a retained renderer issues one draw call instead of one per
  /// block. Merged geometry is culled as a single bounding box, so keep
  /// batches to what is plausibly visible together (a room, not a city).
  ///
  /// Throws [ArgumentError] when [placements] is empty or a matrix is not
  /// invertible (a zero scale axis), since that would produce NaN normals.
  static Geometry merged(Iterable<GeometryPlacement> placements) {
    final list = placements.toList(growable: false);
    if (list.isEmpty) {
      throw ArgumentError.value(placements, 'placements', 'must not be empty');
    }
    var vertexTotal = 0;
    var indexTotal = 0;
    for (final placement in list) {
      vertexTotal += placement.geometry.vertexCount;
      indexTotal += placement.geometry.indices.length;
    }
    final vertices = List<Vector3>.filled(vertexTotal, Vector3.zero());
    final normals = List<Vector3>.filled(vertexTotal, Vector3.zero());
    final uvs = List<Vector2>.filled(vertexTotal, Vector2.zero());
    final indices = List<int>.filled(indexTotal, 0);
    var vertexOffset = 0;
    var indexOffset = 0;
    final normalMatrix = Matrix3.zero();
    for (final placement in list) {
      final geometry = placement.geometry;
      final transform = placement.transform;
      final inverse = Matrix4.zero();
      final determinant = inverse.copyInverse(transform);
      if (determinant == 0.0 || !determinant.isFinite) {
        throw ArgumentError(
          'Geometry.merged: placement transform is not invertible.',
        );
      }
      // Normal matrix = inverse-transpose of the upper 3×3.
      inverse.copyRotation(normalMatrix);
      normalMatrix.transpose();
      final flipWinding = determinant < 0;
      for (var i = 0; i < geometry.vertexCount; i++) {
        vertices[vertexOffset + i] = transform.transformed3(
          geometry.vertices[i],
        );
        final n = normalMatrix.transformed(geometry.normals[i]);
        if (n.length2 > 0) n.normalize();
        normals[vertexOffset + i] = n;
        uvs[vertexOffset + i] = geometry.uvs[i].clone();
      }
      final source = geometry.indices;
      for (var i = 0; i < source.length; i += 3) {
        // A mirroring transform reverses the triangle winding; swap two
        // indices so front faces stay front faces.
        indices[indexOffset + i] = source[i] + vertexOffset;
        indices[indexOffset + i + 1] =
            source[flipWinding ? i + 2 : i + 1] + vertexOffset;
        indices[indexOffset + i + 2] =
            source[flipWinding ? i + 1 : i + 2] + vertexOffset;
      }
      vertexOffset += geometry.vertexCount;
      indexOffset += source.length;
    }
    return Geometry(
      vertices: vertices,
      normals: normals,
      uvs: uvs,
      indices: indices,
    );
  }
}

/// One source geometry and the local transform baked into a merged geometry.
class GeometryPlacement {
  const GeometryPlacement(this.geometry, this.transform);

  /// Convenience for the common translate/scale case (no rotation).
  GeometryPlacement.box(
    this.geometry, {
    required Vector3 position,
    required Vector3 scale,
  }) : transform = Matrix4.compose(position, Quaternion.identity(), scale);

  final Geometry geometry;
  final Matrix4 transform;
}

/// A 3D geometry generated by displacing a grid mesh using a depth map list.
class DepthDisplacedGeometry extends Geometry {
  final int widthSegments;
  final int heightSegments;
  final double width;
  final double height;
  final List<double> depthMap;
  final double maxDisplacement;

  DepthDisplacedGeometry({
    required this.widthSegments,
    required this.heightSegments,
    required this.width,
    required this.height,
    required this.depthMap,
    this.maxDisplacement = 1.0,
  }) : super(
         vertices: _buildVertices(
           widthSegments,
           heightSegments,
           width,
           height,
           depthMap,
           maxDisplacement,
         ),
         indices: _buildIndices(widthSegments, heightSegments),
       );

  static List<Vector3> _buildVertices(
    int wSegs,
    int hSegs,
    double w,
    double h,
    List<double> depths,
    double maxDisp,
  ) {
    final verts = <Vector3>[];
    for (var y = 0; y <= hSegs; y++) {
      final v = y / hSegs;
      final posY = (v - 0.5) * h;
      for (var x = 0; x <= wSegs; x++) {
        final u = x / wSegs;
        final posX = (u - 0.5) * w;

        final idx = y * (wSegs + 1) + x;
        final depth = idx < depths.length ? depths[idx] : 0.0;
        final posZ = depth * maxDisp; // Offset along depth axis

        verts.add(Vector3(posX, posY, posZ));
      }
    }
    return verts;
  }

  static List<int> _buildIndices(int wSegs, int hSegs) {
    final indices = <int>[];
    for (var y = 0; y < hSegs; y++) {
      for (var x = 0; x < wSegs; x++) {
        final i0 = y * (wSegs + 1) + x;
        final i1 = i0 + 1;
        final i2 = (y + 1) * (wSegs + 1) + x;
        final i3 = i2 + 1;

        // Triangle 1: i0 -> i1 -> i2
        indices.addAll([i0, i1, i2]);
        // Triangle 2: i1 -> i3 -> i2
        indices.addAll([i1, i3, i2]);
      }
    }
    return indices;
  }
}
