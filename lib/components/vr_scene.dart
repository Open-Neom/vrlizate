import 'dart:ui';

import 'package:flutter/painting.dart' show LinearGradient;

import '../core/camera/vr_camera.dart';
import '../core/projection/stereoscopic_projection.dart';
import '../core/rendering/vr_renderer.dart';
import 'vr_element.dart';

/// A scene containing VR elements that can be rendered stereoscopically.
class VRScene implements VRRenderer {
  final List<VRElement> elements = [];
  final List<VRConnection> connections = [];

  /// Background color.
  Color backgroundColor;

  /// Background gradient (overrides backgroundColor if set).
  LinearGradient? backgroundGradient;

  VRScene({
    this.backgroundColor = const Color(0xFF0A0A1A),
    this.backgroundGradient,
  });

  void addElement(VRElement element) => elements.add(element);
  void addConnection(VRConnection connection) => connections.add(connection);

  void clear() {
    elements.clear();
    connections.clear();
  }

  @override
  void renderEye(
    Canvas canvas,
    Size viewportSize,
    VRCamera camera,
    StereoscopicProjection projection,
    bool isLeftEye,
  ) {
    // Background
    if (backgroundGradient != null) {
      canvas.drawRect(
        Offset.zero & viewportSize,
        Paint()
          ..shader = backgroundGradient!.createShader(
            Offset.zero & viewportSize,
          ),
      );
    } else {
      canvas.drawRect(
        Offset.zero & viewportSize,
        Paint()..color = backgroundColor,
      );
    }

    // Collect and sort by depth
    final projected = <_ProjectedElement>[];

    for (final element in elements) {
      if (!element.visible) continue;

      final point = isLeftEye
          ? projection.projectLeft(
              element.position,
              camera,
              viewportSize.width,
              viewportSize.height,
            )
          : projection.projectRight(
              element.position,
              camera,
              viewportSize.width,
              viewportSize.height,
            );

      if (!point.visible || point.depth <= 0) continue;

      projected.add(
        _ProjectedElement(
          element: element,
          screenX: point.screenX,
          screenY: point.screenY,
          depth: point.depth,
        ),
      );
    }

    // Z-sort (far to near)
    projected.sort((a, b) => b.depth.compareTo(a.depth));

    // Render connections first
    for (final conn in connections) {
      final pa = isLeftEye
          ? projection.projectLeft(
              conn.a.position,
              camera,
              viewportSize.width,
              viewportSize.height,
            )
          : projection.projectRight(
              conn.a.position,
              camera,
              viewportSize.width,
              viewportSize.height,
            );
      final pb = isLeftEye
          ? projection.projectLeft(
              conn.b.position,
              camera,
              viewportSize.width,
              viewportSize.height,
            )
          : projection.projectRight(
              conn.b.position,
              camera,
              viewportSize.width,
              viewportSize.height,
            );

      if (pa.visible && pb.visible) {
        canvas.drawLine(
          pa.offset,
          pb.offset,
          Paint()
            ..color = conn.color
            ..strokeWidth = conn.strokeWidth,
        );
      }
    }

    // Render elements
    for (final p in projected) {
      final scale = (projection.projectionScale / p.depth).clamp(0.1, 5.0);
      p.element.render(canvas, p.screenX, p.screenY, p.depth, scale);
    }
  }
}

class _ProjectedElement {
  final VRElement element;
  final double screenX;
  final double screenY;
  final double depth;

  const _ProjectedElement({
    required this.element,
    required this.screenX,
    required this.screenY,
    required this.depth,
  });
}
