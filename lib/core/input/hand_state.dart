import 'package:vector_math/vector_math.dart';

import 'controller_state.dart';

/// 25 joints per hand following the OpenXR hand tracking standard.
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

/// Represents the tracked state of a hand with 25 joints.
class HandState {
  final ControllerHand hand;
  final Map<HandJoint, Vector3> joints;
  bool tracked;

  HandState({
    required this.hand,
    Map<HandJoint, Vector3>? joints,
    this.tracked = false,
  }) : joints = joints ?? {};

  Vector3? joint(HandJoint j) => joints[j];

  Vector3? get palmPosition => joints[HandJoint.palm];
  Vector3? get indexTipPosition => joints[HandJoint.indexTip];
  Vector3? get thumbTipPosition => joints[HandJoint.thumbTip];

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

  /// Ray from palm through index tip (for pointing/selection).
  Ray? get pointingRay {
    final palm = palmPosition;
    final indexTip = indexTipPosition;
    if (palm == null || indexTip == null) return null;
    final dir = (indexTip - palm)..normalize();
    return Ray.originDirection(indexTip, dir);
  }
}
