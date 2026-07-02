import 'dart:ui';
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart' show Matrix4;

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
  late final List<int> indices;

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
    indices = [];

    for (var y = 0; y <= resolution; y++) {
      for (var x = 0; x <= resolution; x++) {
        // Normalized coordinates [-1, 1]
        final nx = (x / resolution) * 2 - 1;
        final ny = (y / resolution) * 2 - 1;

        originalPoints.add(Offset(nx, ny));
        distortedPoints.add(distort(nx, ny));
      }
    }

    // Pre-compute indices for drawing triangles
    for (var y = 0; y < resolution; y++) {
      for (var x = 0; x < resolution; x++) {
        final i00 = y * (resolution + 1) + x;
        final i10 = i00 + 1;
        final i01 = i00 + (resolution + 1);
        final i11 = i01 + 1;

        // Triangle 1
        indices.add(i00);
        indices.add(i10);
        indices.add(i11);

        // Triangle 2
        indices.add(i00);
        indices.add(i11);
        indices.add(i01);
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

  /// Warps a rendered offline Image onto the target canvas using the pre-computed distortion mesh.
  /// Supports [atwTransform] matrix for Asynchronous Time Warp and [enableChromaticAberration]
  /// for correcting lens chromatic dispersion via multi-pass RGB blend.
  void drawDistortedImage(
    Canvas canvas,
    Image image,
    Size viewportSize, {
    Matrix4? atwTransform,
    bool enableChromaticAberration = false,
  }) {
    final w = viewportSize.width;
    final h = viewportSize.height;

    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    // Map distorted points [-1, 1] to output viewport coordinates [0, w/h]
    final positions = distortedPoints.map((p) => _toScreen(p, w, h)).toList();

    final shaderMatrix = atwTransform ?? Matrix4.identity();
    final shader = ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      Float64List.fromList(shaderMatrix.storage),
    );

    if (enableChromaticAberration) {
      // Map Green (neutral), Red (expanded 1.008), and Blue (contracted 0.992) texture coords
      final greenCoords = originalPoints.map((p) => _toScreen(p, imgW, imgH)).toList();

      final redCoords = originalPoints.map((p) {
        final shifted = Offset(p.dx * 1.008, p.dy * 1.008);
        return _toScreen(shifted, imgW, imgH);
      }).toList();

      final blueCoords = originalPoints.map((p) {
        final shifted = Offset(p.dx * 0.992, p.dy * 0.992);
        return _toScreen(shifted, imgW, imgH);
      }).toList();

      // Draw Red channel
      final redVertices = Vertices(
        VertexMode.triangles,
        positions,
        textureCoordinates: redCoords,
        indices: indices,
      );
      final redPaint = Paint()
        ..shader = shader
        ..colorFilter = const ColorFilter.matrix([
          1, 0, 0, 0, 0,
          0, 0, 0, 0, 0,
          0, 0, 0, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      canvas.drawVertices(redVertices, BlendMode.srcOver, redPaint);

      // Draw Green channel (BlendMode.plus)
      final greenVertices = Vertices(
        VertexMode.triangles,
        positions,
        textureCoordinates: greenCoords,
        indices: indices,
      );
      final greenPaint = Paint()
        ..shader = shader
        ..blendMode = BlendMode.plus
        ..colorFilter = const ColorFilter.matrix([
          0, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 0, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      canvas.drawVertices(greenVertices, BlendMode.srcOver, greenPaint);

      // Draw Blue channel (BlendMode.plus)
      final blueVertices = Vertices(
        VertexMode.triangles,
        positions,
        textureCoordinates: blueCoords,
        indices: indices,
      );
      final bluePaint = Paint()
        ..shader = shader
        ..blendMode = BlendMode.plus
        ..colorFilter = const ColorFilter.matrix([
          0, 0, 0, 0, 0,
          0, 0, 0, 0, 0,
          0, 0, 1, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      canvas.drawVertices(blueVertices, BlendMode.srcOver, bluePaint);
    } else {
      // Standard single-pass render without aberration correction
      final textureCoords = originalPoints.map((p) => _toScreen(p, imgW, imgH)).toList();

      final vertices = Vertices(
        VertexMode.triangles,
        positions,
        textureCoordinates: textureCoords,
        indices: indices,
      );

      canvas.drawVertices(
        vertices,
        BlendMode.srcOver,
        Paint()..shader = shader,
      );
    }
  }

  /// Draws the distortion mesh on a canvas as a wireframe grid (for debug).
  void applyToCanvas(
    Canvas canvas,
    Size viewportSize, {
    bool isLeftEye = true,
  }) {
    final w = viewportSize.width;
    final h = viewportSize.height;

    // Draw the warped mesh as wireframe
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

        if (_isOutOfBounds(dst00, w, h) &&
            _isOutOfBounds(dst10, w, h) &&
            _isOutOfBounds(dst01, w, h) &&
            _isOutOfBounds(dst11, w, h)) {
          continue;
        }

        final path = Path()
          ..moveTo(dst00.dx, dst00.dy)
          ..lineTo(dst10.dx, dst10.dy)
          ..lineTo(dst11.dx, dst11.dy)
          ..lineTo(dst01.dx, dst01.dy)
          ..close();

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
