import 'dart:ui';

import 'package:vector_math/vector_math.dart';

import 'billboard.dart';

/// A floating UI panel in VR space.
/// Renders a rectangle with background, border, and content callback.
class SpatialPanel extends Billboard {
  /// Panel width in world units.
  double panelWidth;

  /// Panel height in world units.
  double panelHeight;

  Color backgroundColor;
  Color borderColor;
  double borderWidth;
  double cornerRadius;
  double opacity;

  /// Custom render callback for panel content.
  void Function(Canvas canvas, Size panelSize)? onRenderContent;

  SpatialPanel({
    super.name = 'panel',
    required super.cameraRig,
    this.panelWidth = 1.0,
    this.panelHeight = 0.6,
    this.backgroundColor = const Color(0xE0161B22),
    this.borderColor = const Color(0xFF30363D),
    this.borderWidth = 1,
    this.cornerRadius = 8,
    this.opacity = 1.0,
    this.onRenderContent,
    super.lockY = true,
  });

  @override
  void onRender(Canvas canvas, Matrix4 viewProjection) {
    // Transform panel center to screen space
    final mvp = viewProjection * worldMatrix;
    final center4 = mvp.transformed(Vector4(0, 0, 0, 1));
    if (center4.w <= 0.001) return;

    final ndcX = center4.x / center4.w;
    final ndcY = center4.y / center4.w;

    // Approximate screen-space size based on depth
    final depth = center4.w;
    final scale = 1.0 / depth; // World units to NDC at this depth
    final screenW = panelWidth * scale;
    final screenH = panelHeight * scale;

    final screenX = ndcX;
    final screenY = ndcY;

    canvas.save();
    canvas.translate(screenX, screenY);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: screenW,
      height: screenH,
    );

    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(cornerRadius / (depth * 400.0)),
    );

    // Background
    canvas.drawRRect(
      rrect,
      Paint()..color = backgroundColor.withValues(alpha: opacity),
    );

    // Border
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth / (depth * 400.0),
    );

    // Content
    if (onRenderContent != null) {
      canvas.clipRRect(rrect);
      canvas.translate(-screenW / 2, -screenH / 2);
      canvas.save();
      canvas.scale(1.0 / 400.0, 1.0 / 400.0);
      onRenderContent!(canvas, Size(screenW * 400.0, screenH * 400.0));
      canvas.restore();
    }

    canvas.restore();
  }
}
