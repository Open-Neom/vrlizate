import 'dart:ui';

/// Simple bloom effect applied as a post-process overlay.
/// Draws bright areas with gaussian blur to simulate light bleed.
class BloomEffect {
  double intensity;
  double threshold;
  double radius;
  bool enabled;

  BloomEffect({
    this.intensity = 0.5,
    this.threshold = 0.7,
    this.radius = 20,
    this.enabled = true,
  });

  /// Applies bloom to the canvas by drawing a blurred overlay of bright areas.
  void apply(Canvas canvas, Size size) {
    if (!enabled || intensity <= 0) return;

    // Simulate bloom with a bright glow overlay at center
    // For a real implementation, this would sample the rendered frame
    // and blur bright pixels. With Canvas API, we approximate with a radial glow.
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(
      center,
      size.width * 0.4,
      Paint()
        ..color = Color.fromARGB((intensity * 30).toInt(), 255, 255, 255)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius)
        ..blendMode = BlendMode.screen,
    );
  }
}
