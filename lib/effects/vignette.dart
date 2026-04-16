import 'dart:math';
import 'dart:ui';

import 'package:flutter/painting.dart' show RadialGradient, Alignment;

/// Vignette effect for VR lens simulation.
/// Darkens the edges of each eye viewport to simulate lens optics.
class VignetteEffect {
  /// Inner radius where vignette starts (0-1, relative to viewport).
  double innerRadius;

  /// Outer radius where vignette reaches full darkness (0-1).
  double outerRadius;

  /// Maximum darkness at edges (0-1).
  double darkness;

  bool enabled;

  VignetteEffect({
    this.innerRadius = 0.5,
    this.outerRadius = 1.0,
    this.darkness = 0.95,
    this.enabled = true,
  });

  /// Draws the vignette on a single eye viewport.
  void apply(Canvas canvas, Size viewportSize) {
    if (!enabled) return;

    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final radius = min(viewportSize.width, viewportSize.height) * 0.5;

    canvas.drawRect(
      Offset.zero & viewportSize,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: outerRadius,
          colors: [
            const Color(0x00000000),
            const Color(0x00000000),
            Color.fromARGB((darkness * 128).toInt(), 0, 0, 0),
            Color.fromARGB((darkness * 255).toInt(), 0, 0, 0),
          ],
          stops: [0.0, innerRadius, outerRadius * 0.85, outerRadius],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  /// Draws the circular lens frame for VR headset simulation.
  void drawLensFrame(Canvas canvas, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final radius = min(viewportSize.width, viewportSize.height) * 0.48;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xCC000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
}
