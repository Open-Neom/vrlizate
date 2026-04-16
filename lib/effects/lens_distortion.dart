import 'dart:ui';

/// Lens distortion parameters for VR optics.
/// Barrel distortion corrects for the magnification effect of VR lenses.
class LensDistortion {
  /// Distortion coefficient K1 (barrel distortion).
  final double k1;

  /// Distortion coefficient K2 (fine-tuning).
  final double k2;

  /// Chromatic aberration offset in pixels.
  final double chromaticAberration;

  const LensDistortion({
    this.k1 = 0.22,
    this.k2 = 0.24,
    this.chromaticAberration = 0,
  });

  /// Google Cardboard v2 defaults.
  static const cardboard = LensDistortion(k1: 0.34, k2: 0.55);

  /// No distortion (for testing).
  static const none = LensDistortion(k1: 0, k2: 0);

  /// Applies barrel distortion to a normalized coordinate (-1 to 1).
  Offset distort(double nx, double ny) {
    final r2 = nx * nx + ny * ny;
    final factor = 1 + k1 * r2 + k2 * r2 * r2;
    return Offset(nx * factor, ny * factor);
  }

  /// Applies distortion to a screen coordinate within a viewport.
  Offset distortScreen(
    double screenX,
    double screenY,
    double width,
    double height,
  ) {
    // Normalize to -1..1
    final nx = (screenX / width) * 2 - 1;
    final ny = (screenY / height) * 2 - 1;

    final distorted = distort(nx, ny);

    // Back to screen coordinates
    return Offset(
      (distorted.dx + 1) / 2 * width,
      (distorted.dy + 1) / 2 * height,
    );
  }
}
