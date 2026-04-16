import 'package:vector_math/vector_math.dart';

import '../scene/node.dart';

/// A bone in a skeleton hierarchy.
class Bone extends Node {
  /// Inverse bind matrix for skinning.
  Matrix4 inverseBindMatrix;

  /// Length of the bone (for debug rendering).
  double length;

  Bone({super.name = 'bone', Matrix4? inverseBindMatrix, this.length = 0.1})
    : inverseBindMatrix = inverseBindMatrix ?? Matrix4.identity();

  /// The skinning matrix: worldMatrix * inverseBindMatrix.
  Matrix4 get skinningMatrix {
    return worldMatrix * inverseBindMatrix;
  }
}

/// A skeleton is a hierarchy of bones used for mesh deformation.
class Skeleton {
  final Bone root;
  final List<Bone> bones;

  Skeleton({required this.root, required this.bones});

  /// Creates a simple humanoid skeleton.
  factory Skeleton.humanoid() {
    final hip = Bone(name: 'hip', length: 0.15);

    final spine = Bone(name: 'spine', length: 0.3);
    hip.addChild(spine);

    final neck = Bone(name: 'neck', length: 0.1);
    spine.addChild(neck);

    final head = Bone(name: 'head', length: 0.15);
    neck.addChild(head);

    final leftShoulder = Bone(name: 'leftShoulder', length: 0.15);
    spine.addChild(leftShoulder);
    final leftElbow = Bone(name: 'leftElbow', length: 0.25);
    leftShoulder.addChild(leftElbow);
    final leftHand = Bone(name: 'leftHand', length: 0.1);
    leftElbow.addChild(leftHand);

    final rightShoulder = Bone(name: 'rightShoulder', length: 0.15);
    spine.addChild(rightShoulder);
    final rightElbow = Bone(name: 'rightElbow', length: 0.25);
    rightShoulder.addChild(rightElbow);
    final rightHand = Bone(name: 'rightHand', length: 0.1);
    rightElbow.addChild(rightHand);

    final leftHip = Bone(name: 'leftHip', length: 0.3);
    hip.addChild(leftHip);
    final leftKnee = Bone(name: 'leftKnee', length: 0.3);
    leftHip.addChild(leftKnee);
    final leftFoot = Bone(name: 'leftFoot', length: 0.1);
    leftKnee.addChild(leftFoot);

    final rightHip = Bone(name: 'rightHip', length: 0.3);
    hip.addChild(rightHip);
    final rightKnee = Bone(name: 'rightKnee', length: 0.3);
    rightHip.addChild(rightKnee);
    final rightFoot = Bone(name: 'rightFoot', length: 0.1);
    rightKnee.addChild(rightFoot);

    return Skeleton(
      root: hip,
      bones: [
        hip,
        spine,
        neck,
        head,
        leftShoulder,
        leftElbow,
        leftHand,
        rightShoulder,
        rightElbow,
        rightHand,
        leftHip,
        leftKnee,
        leftFoot,
        rightHip,
        rightKnee,
        rightFoot,
      ],
    );
  }

  /// Finds a bone by name.
  Bone? findBone(String name) {
    for (final bone in bones) {
      if (bone.name == name) return bone;
    }
    return null;
  }

  /// Collects all skinning matrices for shader upload.
  List<Matrix4> get skinningMatrices {
    return bones.map((b) => b.skinningMatrix).toList();
  }
}
