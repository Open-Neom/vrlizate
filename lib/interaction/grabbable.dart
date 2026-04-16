import 'package:vector_math/vector_math.dart';

import '../core/input/controller_state.dart';
import '../scene/node.dart';

/// Makes a node grabbable via controller grip or pinch.
class Grabbable {
  final Node node;
  bool isGrabbed = false;
  ControllerHand? grabbedBy;

  /// Offset from controller to node at grab start.
  Vector3 _grabOffset = Vector3.zero();
  Quaternion _grabRotationOffset = Quaternion.identity();

  /// Maximum grab distance.
  double maxGrabDistance;

  void Function(Node node)? onGrabStart;
  void Function(Node node)? onGrabEnd;
  void Function(Node node, Vector3 velocity)? onRelease;

  Vector3 _prevPosition = Vector3.zero();

  Grabbable({
    required this.node,
    this.maxGrabDistance = 2.0,
    this.onGrabStart,
    this.onGrabEnd,
    this.onRelease,
  });

  /// Attempts to grab this node from a controller.
  bool tryGrab(ControllerState controller) {
    if (isGrabbed) return false;

    final dist = (node.worldPosition - controller.position).length;
    if (dist > maxGrabDistance) return false;

    isGrabbed = true;
    grabbedBy = controller.hand;
    _grabOffset = node.worldPosition - controller.position;
    _grabRotationOffset =
        controller.transform.rotation.conjugated() * node.transform.rotation;
    _prevPosition = node.transform.position.clone();
    onGrabStart?.call(node);
    return true;
  }

  /// Updates the grabbed node position to follow the controller.
  void updateGrab(ControllerState controller) {
    if (!isGrabbed || grabbedBy != controller.hand) return;

    _prevPosition = node.transform.position.clone();
    node.transform.position = controller.position + _grabOffset;
    node.transform.rotation =
        controller.transform.rotation * _grabRotationOffset;
    node.onTransformChanged();
  }

  /// Releases the node, optionally with throw velocity.
  void release() {
    if (!isGrabbed) return;

    final velocity = node.transform.position - _prevPosition;
    isGrabbed = false;
    grabbedBy = null;
    onGrabEnd?.call(node);
    onRelease?.call(node, velocity);
  }
}
