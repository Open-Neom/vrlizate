import 'dart:ui';

/// Polynomial radial distortion for VR lens correction.
/// Based on Google Cardboard SDK distortion algorithm.
///
/// Uses a pre-computed mesh grid to warp the rendered image
/// to counteract the lens barrel distortion of VR headsets.
class DistortionMesh {
  /// Distortion coefficients (K1, K2, ...).
  final List<double> coefficients;

  /// Grid resolution (default 40x40 like Cardboard SDK).
  final int resolution;

  /// Screen-to-lens distance in meters.
  final double screenToLensDistance;

  /// Inter-lens distance in meters.
  final double interLensDistance;

  /// Pre-computed distorted UV coordinates.
  late final List<Offset> distortedPoints;
  late final List<Offset> originalPoints;

  DistortionMesh({
    this.coefficients = const [0.441, 0.156],
    this.resolution = 40,
    this.screenToLensDistance = 0.042,
    this.interLensDistance = 0.06,
  }) {
    _computeMesh();
  }

  /// Google Cardboard V1 preset.
  factory DistortionMesh.cardboardV1() => DistortionMesh(
    coefficients: const [0.441, 0.156],
    screenToLensDistance: 0.042,
    interLensDistance: 0.06,
  );

  /// Google Cardboard V2 preset.
  factory DistortionMesh.cardboardV2() => DistortionMesh(
    coefficients: const [0.34, 0.55],
    screenToLensDistance: 0.039,
    interLensDistance: 0.064,
  );

  /// No distortion (flat).
  factory DistortionMesh.none() => DistortionMesh(coefficients: const [0, 0]);

  void _computeMesh() {
    originalPoints = [];
    distortedPoints = [];

    for (var y = 0; y <= resolution; y++) {
      for (var x = 0; x <= resolution; x++) {
        // Normalized coordinates [-1, 1]
        final nx = (x / resolution) * 2 - 1;
        final ny = (y / resolution) * 2 - 1;

        originalPoints.add(Offset(nx, ny));
        distortedPoints.add(distort(nx, ny));
      }
    }
  }

  /// Applies polynomial radial distortion.
  Offset distort(double nx, double ny) {
    final rSquared = nx * nx + ny * ny;
    final factor = distortionFactor(rSquared);
    return Offset(nx * factor, ny * factor);
  }

  double distortionFactor(double rSquared) {
    double rFactor = 1.0;
    double factor = 1.0;
    for (final k in coefficients) {
      rFactor *= rSquared;
      factor += k * rFactor;
    }
    return factor;
  }

  /// Computes inverse distortion using Secant method.
  /// Given a distorted radius, finds the undistorted radius.
  double inverseDistort(double radius) {
    if (radius <= 0.0001) return 0;

    // Secant method with two initial guesses
    double r0 = radius * 0.5;
    double r1 = radius * 0.33;

    double dr0 = r0 * distortionFactor(r0 * r0) - radius;
    double dr1 = r1 * distortionFactor(r1 * r1) - radius;

    for (var i = 0; i < 20; i++) {
      final r2 = r1 - dr1 * ((r1 - r0) / (dr1 - dr0));
      if ((r2 - r1).abs() < 0.0001) return r2;

      r0 = r1;
      dr0 = dr1;
      r1 = r2;
      dr1 = r1 * distortionFactor(r1 * r1) - radius;
    }

    return r1;
  }

  /// Draws the distortion mesh on a canvas, warping the source viewport.
  /// Call this AFTER rendering the scene to apply lens correction.
  void applyToCanvas(
    Canvas canvas,
    Size viewportSize, {
    bool isLeftEye = true,
  }) {
    final w = viewportSize.width;
    final h = viewportSize.height;

    // Draw the warped mesh as triangle strips
    for (var y = 0; y < resolution; y++) {
      for (var x = 0; x < resolution; x++) {
        final i00 = y * (resolution + 1) + x;
        final i10 = i00 + 1;
        final i01 = i00 + (resolution + 1);
        final i11 = i01 + 1;

        final dst00 = _toScreen(distortedPoints[i00], w, h);
        final dst10 = _toScreen(distortedPoints[i10], w, h);
        final dst01 = _toScreen(distortedPoints[i01], w, h);
        final dst11 = _toScreen(distortedPoints[i11], w, h);

        // Check if distorted point is within viewport
        if (_isOutOfBounds(dst00, w, h) &&
            _isOutOfBounds(dst10, w, h) &&
            _isOutOfBounds(dst01, w, h) &&
            _isOutOfBounds(dst11, w, h)) {
          continue;
        }

        // Draw the warped quad as wireframe (for debug) or filled mesh
        final path = Path()
          ..moveTo(dst00.dx, dst00.dy)
          ..lineTo(dst10.dx, dst10.dy)
          ..lineTo(dst11.dx, dst11.dy)
          ..lineTo(dst01.dx, dst01.dy)
          ..close();

        // In a real GPU pipeline, this would be a textured mesh.
        // On Canvas, we show the distortion grid for visualization.
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0x15FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );
      }
    }
  }

  Offset _toScreen(Offset normalized, double width, double height) {
    return Offset(
      (normalized.dx + 1) * 0.5 * width,
      (normalized.dy + 1) * 0.5 * height,
    );
  }

  bool _isOutOfBounds(Offset point, double width, double height) {
    return point.dx < -50 ||
        point.dx > width + 50 ||
        point.dy < -50 ||
        point.dy > height + 50;
  }
}
