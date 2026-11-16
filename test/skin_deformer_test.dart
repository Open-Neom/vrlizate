import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

class _CustomMatrixBone extends Bone {
  _CustomMatrixBone({required this.customMatrix});

  final Matrix4 customMatrix;

  @override
  Matrix4 get skinningMatrix => customMatrix;
}

void main() {
  group('SkinDeformer (SAIA-ENGINE-005 & zero-alloc LBS)', () {
    test(
      'pure bone translation moves vertex position without tilting surface normal',
      () {
        final root = Bone(name: 'root');
        root.transform.position = Vector3(5.0, -3.0, 2.0);
        root.onTransformChanged();
        final skeleton = Skeleton(root: root, bones: [root]);
        final geom = Geometry(
          vertices: [Vector3(1.0, 2.0, 3.0)],
          normals: [Vector3(0.0, 1.0, 0.0)],
          indices: const [0, 0, 0],
        );

        final deformer = SkinDeformer(
          baseGeometry: geom,
          skeleton: skeleton,
          jointIndices: const [
            [0, 0, 0, 0],
          ],
          jointWeights: const [
            [1.0, 0.0, 0.0, 0.0],
          ],
        );

        final out = deformer.deform();
        expect(out.vertices.single.x, closeTo(6.0, 1e-5));
        expect(out.vertices.single.y, closeTo(-1.0, 1e-5));
        expect(out.vertices.single.z, closeTo(5.0, 1e-5));

        // Before SAIA-ENGINE-005 fix, transformed3(baseNorm) produced normalize(5, -2, 2).
        expect(out.normals.single.x, closeTo(0.0, 1e-6));
        expect(out.normals.single.y, closeTo(1.0, 1e-6));
        expect(out.normals.single.z, closeTo(0.0, 1e-6));
      },
    );

    test(
      'non-uniform bone scale uses inverse-transpose 3x3 normal matrix so normal stays perpendicular to tangent',
      () {
        final root = Bone(name: 'root');
        root.transform.position = Vector3(4.0, 1.0, -2.0);
        root.transform.scale = Vector3(2.0, 1.0, 1.0);
        root.onTransformChanged();
        final skeleton = Skeleton(root: root, bones: [root]);

        // Diagonal slope x + y = 1: vertices (1,0,0) and (0,1,0) have normal (1,1,0)/sqrt(2).
        final invSqrt2 = 1.0 / math.sqrt(2.0);
        final geom = Geometry(
          vertices: [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)],
          normals: [
            Vector3(invSqrt2, invSqrt2, 0.0),
            Vector3(invSqrt2, invSqrt2, 0.0),
          ],
          indices: const [0, 1, 0],
        );

        final deformer = SkinDeformer(
          baseGeometry: geom,
          skeleton: skeleton,
          jointIndices: const [
            [0, 0, 0, 0],
            [0, 0, 0, 0],
          ],
          jointWeights: const [
            [1.0, 0.0, 0.0, 0.0],
            [1.0, 0.0, 0.0, 0.0],
          ],
        );

        final out = deformer.deform();
        final tangent = out.vertices[1] - out.vertices[0]; // (-2, 1, 0)
        expect(tangent.x, closeTo(-2.0, 1e-5));
        expect(tangent.y, closeTo(1.0, 1e-5));

        final n = out.normals[0];
        expect(n.length, closeTo(1.0, 1e-5));
        // Perpendicularity check: dot(n, tangent) == 0 -> n = normalize(0.5, 1.0, 0.0).
        expect(n.dot(tangent), closeTo(0.0, 1e-5));
        expect(n.x, closeTo(1.0 / math.sqrt(5.0), 1e-5));
        expect(n.y, closeTo(2.0 / math.sqrt(5.0), 1e-5));
      },
    );

    test(
      'collapsed zero-scale bone and out-of-range joint indices never emit NaN normals',
      () {
        final root = Bone(name: 'collapsed');
        root.transform.scale = Vector3.zero();
        root.transform.position = Vector3(10.0, 20.0, 30.0);
        root.onTransformChanged();
        final skeleton = Skeleton(root: root, bones: [root]);
        final geom = Geometry(
          vertices: [Vector3(1.0, 1.0, 1.0)],
          normals: [Vector3(0.0, 0.0, 1.0)],
          indices: const [0, 0, 0],
        );

        final deformer = SkinDeformer(
          baseGeometry: geom,
          skeleton: skeleton,
          jointIndices: const [
            [0, -1, 99],
          ],
          jointWeights: const [
            [1.0, 0.5, 0.5],
          ],
        );

        final out = deformer.deform();
        final n = out.normals.single;
        expect(n.x.isFinite && n.y.isFinite && n.z.isFinite, isTrue);
        expect(n.length, closeTo(1.0, 1e-5));

        final flatPos = Float32List(3);
        final flatNorm = Float32List(3);
        deformer.deformInto(flatPos, flatNorm);
        expect(flatPos[0], closeTo(10.0, 1e-5));
        expect(flatNorm[2], closeTo(1.0, 1e-5));
      },
    );

    test('deform reuses Vector3 instances in-place across frames and matches deformInto', () {
      final skeleton = Skeleton.humanoid();
      skeleton.bones[1].transform.rotation = Quaternion.axisAngle(
        Vector3(0, 0, 1),
        0.4,
      );
      skeleton.bones[1].onTransformChanged();
      final geom = CubeGeometry(size: 1.0);
      final deformer = SkinDeformer.uniform(geometry: geom, skeleton: skeleton);

      final first = deformer.deform();
      final firstVertexRef = first.vertices.first;
      final firstNormalRef = first.normals.first;

      skeleton.bones[1].transform.rotation = Quaternion.axisAngle(
        Vector3(0, 1, 0),
        -0.3,
      );
      skeleton.bones[1].onTransformChanged();
      final second = deformer.deform();
      expect(identical(second.vertices.first, firstVertexRef), isTrue);
      expect(identical(second.normals.first, firstNormalRef), isTrue);

      final flatPos = Float32List(geom.vertexCount * 3);
      final flatNorm = Float32List(geom.vertexCount * 3);
      deformer.deformInto(flatPos, flatNorm);
      for (var i = 0; i < geom.vertexCount; i++) {
        expect(flatPos[i * 3], closeTo(second.vertices[i].x, 1e-6));
        expect(flatPos[i * 3 + 1], closeTo(second.vertices[i].y, 1e-6));
        expect(flatPos[i * 3 + 2], closeTo(second.vertices[i].z, 1e-6));
        expect(flatNorm[i * 3], closeTo(second.normals[i].x, 1e-6));
        expect(flatNorm[i * 3 + 1], closeTo(second.normals[i].y, 1e-6));
        expect(flatNorm[i * 3 + 2], closeTo(second.normals[i].z, 1e-6));
      }
    });

    test(
      'SAIA-ENGINE-008: honors Bone subclass overriding skinningMatrix while worldMatrix stays identity',
      () {
        final customBone = _CustomMatrixBone(
          customMatrix: Matrix4.translationValues(5.0, 0.0, 0.0),
        );
        final skeleton = Skeleton(root: customBone, bones: [customBone]);
        final geom = Geometry(
          vertices: [Vector3(1.0, 2.0, 3.0)],
          normals: [Vector3(0.0, 1.0, 0.0)],
          indices: const [0, 0, 0],
        );
        final deformer = SkinDeformer(
          baseGeometry: geom,
          skeleton: skeleton,
          jointIndices: const [
            [0, 0, 0, 0],
          ],
          jointWeights: const [
            [1.0, 0.0, 0.0, 0.0],
          ],
        );

        final out = deformer.deform();
        expect(out.vertices.single.x, closeTo(6.0, 1e-5));
        expect(out.vertices.single.y, closeTo(2.0, 1e-5));
        expect(out.vertices.single.z, closeTo(3.0, 1e-5));
        expect(out.normals.single.x, closeTo(0.0, 1e-6));
        expect(out.normals.single.y, closeTo(1.0, 1e-6));
        expect(out.normals.single.z, closeTo(0.0, 1e-6));
      },
    );
  });
}
