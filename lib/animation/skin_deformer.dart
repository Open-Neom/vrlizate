import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../scene/geometry.dart';
import 'skeleton.dart';

/// Deforms mesh vertices using skeletal bone weights.
///
/// Implements CPU-based linear blend skinning (LBS) reading
/// [Skeleton.skinningMatrices] (and thus honoring custom [Bone.skinningMatrix]
/// or [Skeleton] overrides). Vertex normals are transformed per bone via the
/// upper-left `3x3` inverse-transpose `(M_3x3^-1)^T` without bone translation:
/// exact for rigid transforms, uniform scale, and single-influence non-uniform
/// scale, and a standard LBS approximation where multiple differently
/// non-uniformly scaled bones blend on the same vertex.
class SkinDeformer {
  final Geometry baseGeometry;
  final Skeleton skeleton;

  /// Joint indices per vertex (up to 4 joints influence per vertex).
  final List<List<int>> jointIndices;

  /// Joint weights per vertex (sum to 1.0).
  final List<List<double>> jointWeights;

  /// Cached deformed vertices updated in-place across [deform] calls.
  late final List<Vector3> _deformedVertices;
  late final List<Vector3> _deformedNormals;

  Float32List _bonePosMat16 = Float32List(0);
  Float32List _boneNormMat9 = Float32List(0);

  SkinDeformer({
    required this.baseGeometry,
    required this.skeleton,
    required this.jointIndices,
    required this.jointWeights,
  }) {
    _deformedVertices = List<Vector3>.generate(
      baseGeometry.vertexCount,
      (i) => baseGeometry.vertices[i].clone(),
      growable: false,
    );
    _deformedNormals = List<Vector3>.generate(
      baseGeometry.vertexCount,
      (i) => baseGeometry.normals[i].clone(),
      growable: false,
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

  int _prepareBoneTables() {
    final skinMatrices = skeleton.skinningMatrices;
    final boneCount = skinMatrices.length;
    if (_bonePosMat16.length < boneCount * 16) {
      _bonePosMat16 = Float32List(boneCount * 16);
      _boneNormMat9 = Float32List(boneCount * 9);
    }

    for (var b = 0; b < boneCount; b++) {
      final s = skinMatrices[b].storage;
      final pOff = b * 16;
      for (var k = 0; k < 16; k++) {
        _bonePosMat16[pOff + k] = s[k];
      }

      // Upper-left 3x3 entries (column-major):
      // [ a00 a01 a02 ]   [ s[0] s[4] s[8]  ]
      // [ a10 a11 a12 ] = [ s[1] s[5] s[9]  ]
      // [ a20 a21 a22 ]   [ s[2] s[6] s[10] ]
      final a00 = s[0], a10 = s[1], a20 = s[2];
      final a01 = s[4], a11 = s[5], a21 = s[6];
      final a02 = s[8], a12 = s[9], a22 = s[10];

      // Cofactor matrix C = det(A) * (A^-1)^T (exact normal matrix without translation).
      final c00 = a11 * a22 - a12 * a21;
      final c10 = -(a01 * a22 - a02 * a21);
      final c20 = a01 * a12 - a02 * a11;

      final c01 = -(a10 * a22 - a12 * a20);
      final c11 = a00 * a22 - a02 * a20;
      final c21 = -(a00 * a12 - a02 * a10);

      final c02 = a10 * a21 - a11 * a20;
      final c12 = -(a00 * a21 - a01 * a20);
      final c22 = a00 * a11 - a01 * a10;

      final det = a00 * c00 + a01 * c01 + a02 * c02;
      final nOff = b * 9;
      if (det.isFinite && det.abs() > 1e-12) {
        final invDet = 1.0 / det;
        _boneNormMat9[nOff + 0] = c00 * invDet;
        _boneNormMat9[nOff + 1] = c10 * invDet;
        _boneNormMat9[nOff + 2] = c20 * invDet;
        _boneNormMat9[nOff + 3] = c01 * invDet;
        _boneNormMat9[nOff + 4] = c11 * invDet;
        _boneNormMat9[nOff + 5] = c21 * invDet;
        _boneNormMat9[nOff + 6] = c02 * invDet;
        _boneNormMat9[nOff + 7] = c12 * invDet;
        _boneNormMat9[nOff + 8] = c22 * invDet;
      } else if (a00.isFinite &&
          a10.isFinite &&
          a20.isFinite &&
          a01.isFinite &&
          a11.isFinite &&
          a21.isFinite &&
          a02.isFinite &&
          a12.isFinite &&
          a22.isFinite) {
        // Singular/collapsed scale fallback: apply linear 3x3 without translation.
        _boneNormMat9[nOff + 0] = a00;
        _boneNormMat9[nOff + 1] = a10;
        _boneNormMat9[nOff + 2] = a20;
        _boneNormMat9[nOff + 3] = a01;
        _boneNormMat9[nOff + 4] = a11;
        _boneNormMat9[nOff + 5] = a21;
        _boneNormMat9[nOff + 6] = a02;
        _boneNormMat9[nOff + 7] = a12;
        _boneNormMat9[nOff + 8] = a22;
      } else {
        _boneNormMat9[nOff + 0] = 1.0;
        _boneNormMat9[nOff + 1] = 0.0;
        _boneNormMat9[nOff + 2] = 0.0;
        _boneNormMat9[nOff + 3] = 0.0;
        _boneNormMat9[nOff + 4] = 1.0;
        _boneNormMat9[nOff + 5] = 0.0;
        _boneNormMat9[nOff + 6] = 0.0;
        _boneNormMat9[nOff + 7] = 0.0;
        _boneNormMat9[nOff + 8] = 1.0;
      }
    }
    return boneCount;
  }

  /// Deforms vertices and normals directly into flat [outPositions] and
  /// [outNormals] buffers (`vertexCount * 3` floats each) with zero per-vertex
  /// heap allocations.
  void deformInto(Float32List outPositions, Float32List outNormals) {
    final vertexCount = baseGeometry.vertexCount;
    if (outPositions.length < vertexCount * 3) {
      throw RangeError.range(
        outPositions.length,
        vertexCount * 3,
        null,
        'outPositions',
      );
    }
    if (outNormals.length < vertexCount * 3) {
      throw RangeError.range(
        outNormals.length,
        vertexCount * 3,
        null,
        'outNormals',
      );
    }
    _deformCore(outPositions: outPositions, outNormals: outNormals);
  }

  /// Deforms vertices based on current bone transforms.
  /// Call this each frame after updating bone positions.
  Geometry deform() {
    _deformCore();
    return Geometry(
      vertices: _deformedVertices,
      normals: _deformedNormals,
      uvs: baseGeometry.uvs,
      indices: baseGeometry.indices,
    );
  }

  void _deformCore({Float32List? outPositions, Float32List? outNormals}) {
    final boneCount = _prepareBoneTables();
    final vertexCount = baseGeometry.vertexCount;
    final baseVerts = baseGeometry.vertices;
    final baseNorms = baseGeometry.normals;

    for (var i = 0; i < vertexCount; i++) {
      final basePos = baseVerts[i];
      final baseNorm = baseNorms[i];
      final px = basePos.x;
      final py = basePos.y;
      final pz = basePos.z;
      final nx = baseNorm.x;
      final ny = baseNorm.y;
      final nz = baseNorm.z;

      final indices = i < jointIndices.length ? jointIndices[i] : const <int>[];
      final weights = i < jointWeights.length
          ? jointWeights[i]
          : const <double>[];
      final count = math.min(4, math.min(indices.length, weights.length));

      var outPx = 0.0;
      var outPy = 0.0;
      var outPz = 0.0;
      var outNx = 0.0;
      var outNy = 0.0;
      var outNz = 0.0;
      var appliedAny = false;

      for (var j = 0; j < count; j++) {
        final w = weights[j];
        if (!w.isFinite || w <= 0.0001) continue;
        final boneIdx = indices[j];
        if (boneIdx < 0 || boneIdx >= boneCount) continue;
        appliedAny = true;

        final pOff = boneIdx * 16;
        final tx =
            _bonePosMat16[pOff + 0] * px +
            _bonePosMat16[pOff + 4] * py +
            _bonePosMat16[pOff + 8] * pz +
            _bonePosMat16[pOff + 12];
        final ty =
            _bonePosMat16[pOff + 1] * px +
            _bonePosMat16[pOff + 5] * py +
            _bonePosMat16[pOff + 9] * pz +
            _bonePosMat16[pOff + 13];
        final tz =
            _bonePosMat16[pOff + 2] * px +
            _bonePosMat16[pOff + 6] * py +
            _bonePosMat16[pOff + 10] * pz +
            _bonePosMat16[pOff + 14];
        outPx += tx * w;
        outPy += ty * w;
        outPz += tz * w;

        final nOff = boneIdx * 9;
        final rnx =
            _boneNormMat9[nOff + 0] * nx +
            _boneNormMat9[nOff + 3] * ny +
            _boneNormMat9[nOff + 6] * nz;
        final rny =
            _boneNormMat9[nOff + 1] * nx +
            _boneNormMat9[nOff + 4] * ny +
            _boneNormMat9[nOff + 7] * nz;
        final rnz =
            _boneNormMat9[nOff + 2] * nx +
            _boneNormMat9[nOff + 5] * ny +
            _boneNormMat9[nOff + 8] * nz;
        outNx += rnx * w;
        outNy += rny * w;
        outNz += rnz * w;
      }

      if (!appliedAny) {
        outPx = px;
        outPy = py;
        outPz = pz;
        outNx = nx;
        outNy = ny;
        outNz = nz;
      }

      final nLen2 = outNx * outNx + outNy * outNy + outNz * outNz;
      if (nLen2.isFinite && nLen2 > 1e-24) {
        final invLen = 1.0 / math.sqrt(nLen2);
        outNx *= invLen;
        outNy *= invLen;
        outNz *= invLen;
      } else {
        final baseLen2 = nx * nx + ny * ny + nz * nz;
        if (baseLen2.isFinite && baseLen2 > 1e-24) {
          final invBase = 1.0 / math.sqrt(baseLen2);
          outNx = nx * invBase;
          outNy = ny * invBase;
          outNz = nz * invBase;
        } else {
          outNx = 0.0;
          outNy = 1.0;
          outNz = 0.0;
        }
      }

      if (outPositions != null && outNormals != null) {
        final v3 = i * 3;
        outPositions[v3] = outPx;
        outPositions[v3 + 1] = outPy;
        outPositions[v3 + 2] = outPz;
        outNormals[v3] = outNx;
        outNormals[v3 + 1] = outNy;
        outNormals[v3 + 2] = outNz;
      } else {
        _deformedVertices[i].setValues(outPx, outPy, outPz);
        _deformedNormals[i].setValues(outNx, outNy, outNz);
      }
    }
  }
}
