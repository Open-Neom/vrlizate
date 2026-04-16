import 'dart:ui';

/// Distance-based fog effect.
class FogEffect {
  Color color;
  double density;
  double near;
  double far;
  bool enabled;

  FogEffect({
    this.color = const Color(0xFF000000),
    this.density = 0.02,
    this.near = 10,
    this.far = 100,
    this.enabled = false,
  });

  /// Calculates fog factor for a given distance from camera.
  /// Returns 0 (no fog) to 1 (fully fogged).
  double fogFactor(double distance) {
    if (!enabled) return 0;

    // Exponential fog
    final factor = 1 - (1 / (1 + density * distance * distance));
    return factor.clamp(0, 1);
  }

  /// Blends a color with fog based on distance.
  Color applyToColor(Color original, double distance) {
    if (!enabled) return original;
    final factor = fogFactor(distance);
    return Color.lerp(original, color, factor)!;
  }

  /// Draws a full-screen fog overlay.
  void applyOverlay(Canvas canvas, Size size) {
    if (!enabled || density <= 0) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: (density * 10).clamp(0, 0.8)),
    );
  }
}
