import 'dart:ui';

import 'package:flutter/painting.dart' show RadialGradient;
import 'package:flutter/widgets.dart' show CustomPainter;

import '../camera/vr_camera.dart';
import '../projection/stereoscopic_projection.dart';

/// Abstract renderer that VR scenes implement.
abstract class VRRenderer {
  /// Renders the scene for a single eye viewport.
  void renderEye(
    Canvas canvas,
    Size viewportSize,
    VRCamera camera,
    StereoscopicProjection projection,
    bool isLeftEye,
  );
}

/// Paints a VR scene in stereoscopic split-screen mode.
class VRStereoPainter extends CustomPainter {
  final VRRenderer renderer;
  final VRCamera camera;
  final StereoscopicProjection projection;
  final Color dividerColor;
  final double dividerWidth;
  final bool showLensVignette;

  VRStereoPainter({
    required this.renderer,
    required this.camera,
    required this.projection,
    this.dividerColor = const Color(0xFF000000),
    this.dividerWidth = 4,
    this.showLensVignette = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final halfWidth = size.width / 2;
    final viewportSize = Size(halfWidth, size.height);

    // Left eye
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, halfWidth, size.height));
    renderer.renderEye(canvas, viewportSize, camera, projection, true);
    if (showLensVignette) _drawVignette(canvas, viewportSize, Offset.zero);
    canvas.restore();

    // Right eye
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(halfWidth, 0, halfWidth, size.height));
    canvas.translate(halfWidth, 0);
    renderer.renderEye(canvas, viewportSize, camera, projection, false);
    if (showLensVignette) _drawVignette(canvas, viewportSize, Offset.zero);
    canvas.restore();

    // Center divider
    canvas.drawRect(
      Rect.fromLTWH(halfWidth - dividerWidth / 2, 0, dividerWidth, size.height),
      Paint()..color = dividerColor,
    );
  }

  void _drawVignette(Canvas canvas, Size viewport, Offset offset) {
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final radius = viewport.height / 2;

    canvas.drawCircle(
      center + offset,
      radius,
      Paint()
        ..shader =
            const RadialGradient(
              colors: [Color(0x00000000), Color(0x00000000), Color(0xF0000000)],
              stops: [0.0, 0.7, 1.0],
            ).createShader(
              Rect.fromCircle(center: center + offset, radius: radius),
            ),
    );
  }

  @override
  bool shouldRepaint(VRStereoPainter oldDelegate) => true;
}

/// Paints a VR scene in monoscopic (single eye) mode.
class VRMonoPainter extends CustomPainter {
  final VRRenderer renderer;
  final VRCamera camera;
  final StereoscopicProjection projection;

  VRMonoPainter({
    required this.renderer,
    required this.camera,
    required this.projection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    renderer.renderEye(canvas, size, camera, projection, true);
  }

  @override
  bool shouldRepaint(VRMonoPainter oldDelegate) => true;
}
