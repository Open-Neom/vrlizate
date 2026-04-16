import 'package:vector_math/vector_math.dart';

import '../scene/geometry.dart';
import 'skeleton.dart';

/// Deforms mesh vertices using skeletal bone weights.
/// CPU-based linear blend skinning (LBS).
class SkinDeformer {
  final Geometry baseGeometry;
  final Skeleton skeleton;

  /// Joint indices per vertex (4 joints max influence per vertex).
  final List<List<int>> jointIndices;

  /// Joint weights per vertex (sum to 1.0).
  final List<List<double>> jointWeights;

  /// Cached deformed vertices.
  late List<Vector3> _deformedVertices;
  late List<Vector3> _deformedNormals;

  SkinDeformer({
    required this.baseGeometry,
    required this.skeleton,
    required this.jointIndices,
    required this.jointWeights,
  }) {
    _deformedVertices = List.generate(
      baseGeometry.vertexCount,
      (i) => baseGeometry.vertices[i].clone(),
    );
    _deformedNormals = List.generate(
      baseGeometry.vertexCount,
      (i) => baseGeometry.normals[i].clone(),
    );
  }

  /// Creates a SkinDeformer with uniform weights (all vertices affected equally by nearest bone).
  factory SkinDeformer.uniform({
    required Geometry geometry,
    required Skeleton skeleton,
  }) {
    final jointIdx = <List<int>>[];
    final jointWts = <List<double>>[];

    for (var i = 0; i < geometry.vertexCount; i++) {
      // Find nearest bone
      final pos = geometry.vertices[i];
      int nearestBone = 0;
      double nearestDist = double.infinity;

      for (var j = 0; j < skeleton.bones.length; j++) {
        final boneDist = (skeleton.bones[j].worldPosition - pos).length;
        if (boneDist < nearestDist) {
          nearestDist = boneDist;
          nearestBone = j;
        }
      }

      jointIdx.add([nearestBone, 0, 0, 0]);
      jointWts.add([1.0, 0.0, 0.0, 0.0]);
    }

    return SkinDeformer(
      baseGeometry: geometry,
      skeleton: skeleton,
      jointIndices: jointIdx,
      jointWeights: jointWts,
    );
  }

  /// Deforms vertices based on current bone transforms.
  /// Call this each frame after updating bone positions.
  Geometry deform() {
    final skinMatrices = skeleton.skinningMatrices;

    for (var i = 0; i < baseGeometry.vertexCount; i++) {
      final basePos = baseGeometry.vertices[i];
      final baseNorm = baseGeometry.normals[i];
      final indices = jointIndices[i];
      final weights = jointWeights[i];

      var deformedPos = Vector3.zero();
      var deformedNorm = Vector3.zero();

      for (var j = 0; j < 4; j++) {
        if (weights[j] <= 0.0001) continue;
        final boneIdx = indices[j];
        if (boneIdx >= skinMatrices.length) continue;

        final skinMatrix = skinMatrices[boneIdx];
        deformedPos += skinMatrix.transformed3(basePos) * weights[j];
        deformedNorm += skinMatrix.transformed3(baseNorm) * weights[j];
      }

      _deformedVertices[i] = deformedPos;
      _deformedNormals[i] = deformedNorm..normalize();
    }

    return Geometry(
      vertices: _deformedVertices,
      normals: _deformedNormals,
      uvs: baseGeometry.uvs,
      indices: baseGeometry.indices,
    );
  }
}
