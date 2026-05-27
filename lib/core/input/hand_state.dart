import 'package:vector_math/vector_math.dart';

import 'controller_state.dart';

/// Represents a bone connection between a parent and child joint in the hand skeleton.
class HandBone {
  final HandJoint parent;
  final HandJoint child;
  const HandBone(this.parent, this.child);
}

/// 26 joints per hand following the OpenXR hand tracking standard.
enum HandJoint {
  palm,
  wrist,
  thumbMetacarpal,
  thumbProximal,
  thumbDistal,
  thumbTip,
  indexMetacarpal,
  indexProximal,
  indexIntermediate,
  indexDistal,
  indexTip,
  middleMetacarpal,
  middleProximal,
  middleIntermediate,
  middleDistal,
  middleTip,
  ringMetacarpal,
  ringProximal,
  ringIntermediate,
  ringDistal,
  ringTip,
  littleMetacarpal,
  littleProximal,
  littleIntermediate,
  littleDistal,
  littleTip,
}

/// Represents the tracked state of a hand with 26 joints following OpenXR standard.
class HandState {
  final ControllerHand hand;
  final Map<HandJoint, Vector3> joints;
  final Map<HandJoint, Quaternion> orientations;
  bool tracked;

  HandState({
    required this.hand,
    Map<HandJoint, Vector3>? joints,
    Map<HandJoint, Quaternion>? orientations,
    this.tracked = false,
  })  : joints = joints ?? {},
        orientations = orientations ?? {};

  Vector3? joint(HandJoint j) => joints[j];
  Quaternion? jointOrientation(HandJoint j) => orientations[j];

  Vector3? get palmPosition => joints[HandJoint.palm];
  Vector3? get indexTipPosition => joints[HandJoint.indexTip];
  Vector3? get thumbTipPosition => joints[HandJoint.thumbTip];

  /// List of 25 standard bone linkages connecting the 26 joints.
  static const List<HandBone> boneConnections = [
    // Wrist and Palm
    HandBone(HandJoint.wrist, HandJoint.palm),

    // Thumb
    HandBone(HandJoint.wrist, HandJoint.thumbMetacarpal),
    HandBone(HandJoint.thumbMetacarpal, HandJoint.thumbProximal),
    HandBone(HandJoint.thumbProximal, HandJoint.thumbDistal),
    HandBone(HandJoint.thumbDistal, HandJoint.thumbTip),

    // Index
    HandBone(HandJoint.palm, HandJoint.indexMetacarpal),
    HandBone(HandJoint.indexMetacarpal, HandJoint.indexProximal),
    HandBone(HandJoint.indexProximal, HandJoint.indexIntermediate),
    HandBone(HandJoint.indexIntermediate, HandJoint.indexDistal),
    HandBone(HandJoint.indexDistal, HandJoint.indexTip),

    // Middle
    HandBone(HandJoint.palm, HandJoint.middleMetacarpal),
    HandBone(HandJoint.middleMetacarpal, HandJoint.middleProximal),
    HandBone(HandJoint.middleProximal, HandJoint.middleIntermediate),
    HandBone(HandJoint.middleIntermediate, HandJoint.middleDistal),
    HandBone(HandJoint.middleDistal, HandJoint.middleTip),

    // Ring
    HandBone(HandJoint.palm, HandJoint.ringMetacarpal),
    HandBone(HandJoint.ringMetacarpal, HandJoint.ringProximal),
    HandBone(HandJoint.ringProximal, HandJoint.ringIntermediate),
    HandBone(HandJoint.ringIntermediate, HandJoint.ringDistal),
    HandBone(HandJoint.ringDistal, HandJoint.ringTip),

    // Little
    HandBone(HandJoint.palm, HandJoint.littleMetacarpal),
    HandBone(HandJoint.littleMetacarpal, HandJoint.littleProximal),
    HandBone(HandJoint.littleProximal, HandJoint.littleIntermediate),
    HandBone(HandJoint.littleIntermediate, HandJoint.littleDistal),
    HandBone(HandJoint.littleDistal, HandJoint.littleTip),
  ];

  /// Distance between thumb tip and index tip.
  double get pinchDistance {
    final thumb = thumbTipPosition;
    final index = indexTipPosition;
    if (thumb == null || index == null) return double.infinity;
    return (thumb - index).length;
  }

  /// Whether the user is performing a pinch gesture.
  bool get isPinching => pinchDistance < 0.02;

  /// Whether the hand is making a fist (all tips close to palm).
  bool get isFist {
    final palm = palmPosition;
    if (palm == null) return false;

    final tips = [
      HandJoint.indexTip,
      HandJoint.middleTip,
      HandJoint.ringTip,
      HandJoint.littleTip,
    ];

    for (final tip in tips) {
      final pos = joints[tip];
      if (pos == null || (pos - palm).length > 0.05) return false;
    }
    return true;
  }

  /// Whether the index finger is extended (pointing).
  bool get isPointing {
    final palm = palmPosition;
    final indexTip = joints[HandJoint.indexTip];
    final middleTip = joints[HandJoint.middleTip];
    if (palm == null || indexTip == null || middleTip == null) return false;

    return (indexTip - palm).length > 0.08 && (middleTip - palm).length < 0.05;
  }

  /// Whether the hand is completely open and flat (all tips extended far from palm).
  bool get isFlatHand {
    final palm = palmPosition;
    if (palm == null) return false;
    final tips = [
      HandJoint.thumbTip,
      HandJoint.indexTip,
      HandJoint.middleTip,
      HandJoint.ringTip,
      HandJoint.littleTip,
    ];
    for (final tip in tips) {
      final pos = joints[tip];
      if (pos == null || (pos - palm).length < 0.065) return false;
    }
    return true;
  }

  /// Whether the hand is doing a thumbs-up gesture (thumb extended, other fingers curled).
  bool get isThumbsUp {
    final palm = palmPosition;
    final thumb = joints[HandJoint.thumbTip];
    if (palm == null || thumb == null) return false;
    if ((thumb - palm).length < 0.055) return false;

    final otherTips = [
      HandJoint.indexTip,
      HandJoint.middleTip,
      HandJoint.ringTip,
      HandJoint.littleTip,
    ];
    for (final tip in otherTips) {
      final pos = joints[tip];
      if (pos == null || (pos - palm).length > 0.045) return false;
    }
    return true;
  }

  /// Whether the hand is doing a victory/peace gesture (index & middle extended, others curled).
  bool get isVictory {
    final palm = palmPosition;
    final index = joints[HandJoint.indexTip];
    final middle = joints[HandJoint.middleTip];
    if (palm == null || index == null || middle == null) return false;

    if ((index - palm).length < 0.075 || (middle - palm).length < 0.075) return false;

    final curledTips = [
      HandJoint.thumbTip,
      HandJoint.ringTip,
      HandJoint.littleTip,
    ];
    for (final tip in curledTips) {
      final pos = joints[tip];
      if (pos == null || (pos - palm).length > 0.045) return false;
    }
    return true;
  }

  /// Ray from palm through index tip (for pointing/selection).
  Ray? get pointingRay {
    final palm = palmPosition;
    final indexTip = indexTipPosition;
    if (palm == null || indexTip == null) return null;
    final dir = (indexTip - palm)..normalize();
    return Ray.originDirection(indexTip, dir);
  }
}
