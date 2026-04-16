import 'dart:ui';

import 'package:vector_math/vector_math.dart';

import 'light.dart';
import 'node.dart';

/// Shadow configuration for a light source.
class ShadowConfig {
  /// Shadow map resolution (higher = sharper shadows, more expensive).
  int resolution;

  /// Shadow bias to prevent self-shadowing artifacts.
  double bias;

  /// Shadow darkness (0 = invisible, 1 = fully black).
  double darkness;

  /// Maximum shadow distance from camera.
  double maxDistance;

  bool enabled;

  ShadowConfig({
    this.resolution = 512,
    this.bias = 0.005,
    this.darkness = 0.5,
    this.maxDistance = 30,
    this.enabled = true,
  });
}

/// Simple shadow renderer that projects shadows onto the ground plane.
/// Uses a simplified shadow map approach for Canvas rendering.
class ShadowRenderer {
  final ShadowConfig config;

  ShadowRenderer({ShadowConfig? config}) : config = config ?? ShadowConfig();

  /// Renders ground-plane shadows for all nodes illuminated by a directional light.
  void renderShadows(
    Canvas canvas,
    Matrix4 viewProjection,
    Light light,
    List<Node> nodes,
    double groundY,
  ) {
    if (!config.enabled || light.type != LightType.directional) return;

    final shadowPaint = Paint()
      ..color = Color.fromARGB((config.darkness * 100).toInt(), 0, 0, 0);

    for (final node in nodes) {
      if (!node.visible) return;
      final pos = node.worldPosition;

      // Project position onto ground plane along light direction
      if (light.direction.y == 0) continue;
      final t = (groundY - pos.y) / light.direction.y;
      if (t < 0) continue; // Light coming from below

      final shadowPos = Vector3(
        pos.x + light.direction.x * t,
        groundY + 0.01, // Slight offset to prevent z-fighting
        pos.z + light.direction.z * t,
      );

      // Project shadow position to screen
      final clip = viewProjection.transformed(
        Vector4(shadowPos.x, shadowPos.y, shadowPos.z, 1),
      );
      if (clip.w <= 0.001) continue;

      final screenX = clip.x / clip.w;
      final screenY = clip.y / clip.w;
      final dist = (pos - shadowPos).length;

      // Shadow size based on distance (penumbra)
      final size = (0.3 + dist * 0.1).clamp(0.2, 2.0);
      final scale = 100 / clip.w;

      // Draw elliptical shadow
      canvas.save();
      canvas.translate(screenX, screenY);
      canvas.scale(scale * size, scale * size * 0.5); // Flatten on ground
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 1, height: 1),
        shadowPaint..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.3),
      );
      canvas.restore();
    }
  }
}
