import 'dart:ui';

import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, FontWeight;

import '../interaction/pointable.dart';
import '../scene/node.dart';
import 'panel.dart';

/// A clickable 3D button in VR space.
class SpatialButton extends Node {
  final SpatialPanel _panel;
  late final Pointable pointable;

  String label;
  Color labelColor;
  Color idleColor;
  Color hoverColor;
  Color pressColor;

  SpatialButton({
    super.name = 'button',
    required super.transform,
    required this.label,
    required panel,
    this.labelColor = const Color(0xFFFFFFFF),
    this.idleColor = const Color(0xE0161B22),
    this.hoverColor = const Color(0xE01C2333),
    this.pressColor = const Color(0xE02E90FA),
    void Function(Node)? onPress,
  }) : _panel = panel {
    pointable = Pointable(
      node: this,
      onHoverEnter: (_) => _panel.backgroundColor = hoverColor,
      onHoverExit: (_) => _panel.backgroundColor = idleColor,
      onPress: (node, hit) {
        _panel.backgroundColor = pressColor;
        onPress?.call(node);
      },
      onRelease: (_) => _panel.backgroundColor = hoverColor,
    );

    _panel.backgroundColor = idleColor;
    _panel.onRenderContent = _renderLabel;
    addChild(_panel);
  }

  void _renderLabel(Canvas canvas, Size panelSize) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: labelColor,
          fontSize: panelSize.height * 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: panelSize.width);

    textPainter.paint(
      canvas,
      Offset(
        (panelSize.width - textPainter.width) / 2,
        (panelSize.height - textPainter.height) / 2,
      ),
    );
  }
}
