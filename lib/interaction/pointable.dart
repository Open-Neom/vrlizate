import 'dart:ui';

import '../scene/node.dart';
import 'raycast.dart';

/// Makes a node respond to pointer hover and click events.
class Pointable {
  final Node node;
  bool isHovered = false;
  bool isPressed = false;

  void Function(Node node)? onHoverEnter;
  void Function(Node node)? onHoverExit;
  void Function(Node node, RaycastHit hit)? onPress;
  void Function(Node node)? onRelease;

  /// Visual highlight color when hovered.
  Color hoverColor;

  /// Visual highlight color when pressed.
  Color pressColor;

  Pointable({
    required this.node,
    this.onHoverEnter,
    this.onHoverExit,
    this.onPress,
    this.onRelease,
    this.hoverColor = const Color(0x40FFFFFF),
    this.pressColor = const Color(0x80FFFFFF),
  });

  void updateHover(bool hovering) {
    if (hovering && !isHovered) {
      isHovered = true;
      onHoverEnter?.call(node);
    } else if (!hovering && isHovered) {
      isHovered = false;
      isPressed = false;
      onHoverExit?.call(node);
    }
  }

  void press(RaycastHit hit) {
    if (!isHovered) return;
    isPressed = true;
    onPress?.call(node, hit);
  }

  void release() {
    if (!isPressed) return;
    isPressed = false;
    onRelease?.call(node);
  }
}
