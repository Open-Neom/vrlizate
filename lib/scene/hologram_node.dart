import 'dart:math';
import 'dart:ui';
import 'package:vector_math/vector_math.dart';
import '../vrlizate.dart';

/// Advanced Volumetric Hologram Simulation Node implementing multi-pass shell rendering,
/// vertex glitched offsets, time-based flickering, and scanline overlay.
class HologramMeshNode extends LitMeshNode {
  double flickerSpeed;
  double scanLineSpacing;
  double glitchFrequency;
  Color hologramColor;
  
  static double time = 0.0; // Global time tick updated by engine/demo

  Size viewportSize;

  HologramMeshNode({
    required super.name,
    required super.geometry,
    this.flickerSpeed = 12.0,
    this.scanLineSpacing = 8.0,
    this.glitchFrequency = 0.15,
    this.hologramColor = const Color(0x9906B6D4), // Semi-transparent Cyan
    this.viewportSize = const Size(800, 600),
  }) : super(
         material: VRMaterial(
           color: hologramColor,
           emissive: hologramColor.withValues(alpha: 1.0),
           opacity: 0.4,
           wireframe: false,
         ),
       );

  @override
  void onRender(Canvas canvas, Matrix4 viewProjection) {
    if (!visible) return;

    // Calculate time-based flickering
    final flicker = 0.7 + 0.3 * sin(time * flickerSpeed);
    
    // Check for random glitches
    final random = Random();
    final isGlitching = random.nextDouble() < glitchFrequency && (sin(time * 30).abs() > 0.7);
    
    // Save original transform parameters
    final originalScale = transform.scale.clone();
    final originalPosition = transform.position.clone();
    final originalOpacity = material.opacity;

    try {
      // --- Pass 1: Holographic Volumetric Core (Transparent & scaled down) ---
      transform.scale = originalScale * 0.96;
      material.opacity = originalOpacity * 0.4 * flicker;
      super.onRender(canvas, viewProjection);

      // --- Pass 2: Main Holographic Body (Normal scale) ---
      transform.scale = originalScale;
      if (isGlitching) {
        // Apply sci-fi vertex/position glitch offset
        transform.position = originalPosition + Vector3(
          (random.nextDouble() - 0.5) * 0.03,
          (random.nextDouble() - 0.5) * 0.01,
          (random.nextDouble() - 0.5) * 0.03,
        );
      }
      material.opacity = originalOpacity * flicker;
      super.onRender(canvas, viewProjection);

      // --- Pass 3: Volumetric Glow Envelope (Wireframe, scaled up) ---
      transform.position = originalPosition;
      transform.scale = originalScale * 1.04;
      material.opacity = originalOpacity * 0.25 * flicker;
      material.wireframe = true;
      super.onRender(canvas, viewProjection);
      material.wireframe = false; // restore

      // --- Overlay scanline effects directly over screen projection space ---
      _drawScanlines(canvas, viewProjection, viewportSize: viewportSize);

    } finally {
      // Always restore original transform parameters
      transform.scale = originalScale;
      transform.position = originalPosition;
      material.opacity = originalOpacity;
    }
  }

  void _drawScanlines(Canvas canvas, Matrix4 viewProjection, {Size viewportSize = const Size(800, 600)}) {
    final mvp = viewProjection * worldMatrix;
    double minY = double.infinity;
    double maxY = -double.infinity;
    double minX = double.infinity;
    double maxX = -double.infinity;

    final halfWidth = viewportSize.width / 2;
    final halfHeight = viewportSize.height / 2;

    for (final v in geometry.vertices) {
      final clip = mvp.transformed3(v);
      final w = mvp.storage[3] * v.x +
          mvp.storage[7] * v.y +
          mvp.storage[11] * v.z +
          mvp.storage[15];
      if (w <= 0.001) continue;

      final ndcX = clip.x / w;
      final ndcY = clip.y / w;
      
      // Dynamic conversion from NDC to screen coordinates
      final x = (ndcX + 1.0) * halfWidth;
      final y = (1.0 - ndcY) * halfHeight;

      minY = min(minY, y);
      maxY = max(maxY, y);
      minX = min(minX, x);
      maxX = max(maxX, x);
    }

    if (minY == double.infinity || maxY == -double.infinity) return;

    // Draw horizontal scanline bars
    final paint = Paint()
      ..color = hologramColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final spacing = scanLineSpacing;
    for (double y = minY; y < maxY; y += spacing * 2) {
      canvas.drawRect(
        Rect.fromLTRB(minX, y, maxX, min(y + spacing, maxY)),
        paint,
      );
    }
  }
}
