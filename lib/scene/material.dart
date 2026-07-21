import 'dart:ui';
import 'texture.dart';

/// Material defines the visual appearance of a mesh surface.
class VRMaterial {
  Color color;
  Color emissive;
  double opacity;
  double metallic;
  double roughness;
  bool doubleSided;
  bool wireframe;
  BlendMode blendMode;
  VRTexture? map;

  VRMaterial({
    this.color = const Color(0xFFCCCCCC),
    this.emissive = const Color(0xFF000000),
    this.opacity = 1.0,
    this.metallic = 0.0,
    this.roughness = 0.8,
    this.doubleSided = false,
    this.wireframe = false,
    this.blendMode = BlendMode.srcOver,
    this.map,
  });

  bool get isTransparent => opacity < 1.0;

  Paint toPaint({double lightFactor = 1.0}) {
    final r = ((color.r * 255.0).round().clamp(0, 255) * lightFactor)
        .clamp(0, 255)
        .toInt();
    final g = ((color.g * 255.0).round().clamp(0, 255) * lightFactor)
        .clamp(0, 255)
        .toInt();
    final b = ((color.b * 255.0).round().clamp(0, 255) * lightFactor)
        .clamp(0, 255)
        .toInt();
    return Paint()
      ..color = Color.fromARGB((opacity * 255).toInt(), r, g, b)
      ..style = wireframe ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = wireframe ? 1.0 : 0
      ..blendMode = blendMode;
  }

  /// Basic unlit material.
  static VRMaterial unlit({
    Color color = const Color(0xFFFFFFFF),
    double opacity = 1.0,
  }) {
    return VRMaterial(color: color, opacity: opacity);
  }

  /// Emissive glow material.
  static VRMaterial glow({
    Color color = const Color(0xFF00CED1),
    double intensity = 1.0,
  }) {
    return VRMaterial(color: color, emissive: color, opacity: intensity);
  }
}
