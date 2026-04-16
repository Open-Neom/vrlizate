import 'dart:ui';

import 'package:flutter/painting.dart'
    show RadialGradient, LinearGradient, Alignment;

/// Screen-Space Ambient Occlusion approximation for Canvas rendering.
/// Uses a simplified approach: darkens corners and edges of the viewport
/// to simulate ambient light being blocked by nearby surfaces.
class SSAOEffect {
  /// Occlusion radius in normalized screen space.
  double radius;

  /// Occlusion intensity (0 = none, 1 = full).
  double intensity;

  /// Number of sample directions.
  int samples;

  bool enabled;

  SSAOEffect({
    this.radius = 0.3,
    this.intensity = 0.5,
    this.samples = 8,
    this.enabled = false,
  });

  /// Applies SSAO-like darkening to the canvas.
  /// For Canvas rendering, this is an approximation using radial gradients.
  void apply(Canvas canvas, Size size) {
    if (!enabled || intensity <= 0) return;

    final alpha = (intensity * 60).toInt().clamp(0, 255);

    // Corner darkening (simulates ambient occlusion at viewport edges)
    final cornerPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0 - radius,
        colors: [const Color(0x00000000), Color.fromARGB(alpha, 0, 0, 0)],
        stops: const [0.6, 1.0],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, cornerPaint);

    // Edge darkening (top/bottom bands)
    final edgeHeight = size.height * radius * 0.3;
    final edgePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [Color.fromARGB(alpha ~/ 2, 0, 0, 0), const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, edgeHeight));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, edgeHeight), edgePaint);

    // Bottom edge
    final bottomPaint = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.center,
            colors: [
              Color.fromARGB(alpha ~/ 2, 0, 0, 0),
              const Color(0x00000000),
            ],
          ).createShader(
            Rect.fromLTWH(0, size.height - edgeHeight, size.width, edgeHeight),
          );

    canvas.drawRect(
      Rect.fromLTWH(0, size.height - edgeHeight, size.width, edgeHeight),
      bottomPaint,
    );
  }
}
