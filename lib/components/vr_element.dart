import 'dart:ui';

import '../utils/vr_math.dart';

/// Base class for any object rendered in the VR scene.
abstract class VRElement {
  /// Position in 3D world space.
  Offset3D position;

  /// Whether this element is visible.
  bool visible;

  VRElement({required this.position, this.visible = true});

  /// Renders this element at the given projected screen position.
  void render(
    Canvas canvas,
    double screenX,
    double screenY,
    double depth,
    double scale,
  );
}

/// A point/particle in VR space.
class VRParticle extends VRElement {
  final double radius;
  final Color color;
  final double glowRadius;

  VRParticle({
    required super.position,
    this.radius = 3,
    this.color = const Color(0xFFFFFFFF),
    this.glowRadius = 0,
    super.visible,
  });

  @override
  void render(
    Canvas canvas,
    double screenX,
    double screenY,
    double depth,
    double scale,
  ) {
    final r = radius * scale;
    final center = Offset(screenX, screenY);

    // Glow
    if (glowRadius > 0) {
      canvas.drawCircle(
        center,
        (radius + glowRadius) * scale,
        Paint()
          ..color = color.withValues(alpha: 0.2)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * scale),
      );
    }

    // Core
    canvas.drawCircle(center, r, Paint()..color = color);

    // Bright center
    canvas.drawCircle(
      center,
      r * 0.4,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }
}

/// A ring/circle in VR space (rendered as an arc at its projected position).
class VRRing extends VRElement {
  final double ringRadius;
  final Color color;
  final double strokeWidth;

  VRRing({
    required super.position,
    this.ringRadius = 20,
    this.color = const Color(0xFF58A6FF),
    this.strokeWidth = 1.5,
    super.visible,
  });

  @override
  void render(
    Canvas canvas,
    double screenX,
    double screenY,
    double depth,
    double scale,
  ) {
    canvas.drawCircle(
      Offset(screenX, screenY),
      ringRadius * scale,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * scale,
    );
  }
}

/// A line connecting two VR elements.
class VRConnection {
  final VRElement a;
  final VRElement b;
  final Color color;
  final double strokeWidth;

  const VRConnection({
    required this.a,
    required this.b,
    this.color = const Color(0x80FFFFFF),
    this.strokeWidth = 0.5,
  });
}
