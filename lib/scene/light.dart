import 'dart:ui';

import 'package:vector_math/vector_math.dart';

import 'node.dart';

enum LightType { ambient, directional, point, spot }

/// Light source in the scene.
class Light extends Node {
  final LightType type;
  Color color;
  double intensity;

  /// Optional lower-hemisphere color for ambient lights.
  ///
  /// When set, the ambient term becomes a two-color hemisphere: surfaces
  /// facing up receive [color], surfaces facing down receive [groundColor],
  /// and the two blend linearly with the world-space normal's Y component.
  /// This models sky light plus ground bounce (a fill light from below)
  /// without any extra light passes. Null keeps a flat, direction-independent
  /// ambient. Ignored for non-ambient light types.
  Color? groundColor;

  /// Direction for directional/spot lights.
  Vector3 direction;

  /// Range for point/spot lights (0 = infinite).
  double range;

  /// Spot angle in radians (for spot lights only).
  double spotAngle;

  Light({
    super.name = 'light',
    this.type = LightType.directional,
    this.color = const Color(0xFFFFFFFF),
    this.intensity = 1.0,
    this.groundColor,
    Vector3? direction,
    this.range = 0,
    this.spotAngle = 0.5,
  }) : direction = direction ?? Vector3(0, -1, 0.5)
         ..normalize();

  /// Creates a default ambient light.
  ///
  /// Pass [groundColor] for hemisphere ambient (sky above, bounce below); see
  /// [Light.groundColor]. Renderers that only support a flat ambient use the
  /// average of the two colors.
  factory Light.ambient({
    Color color = const Color(0xFF404040),
    Color? groundColor,
    double intensity = 0.3,
  }) {
    return Light(
      name: 'ambient',
      type: LightType.ambient,
      color: color,
      groundColor: groundColor,
      intensity: intensity,
    );
  }

  /// Relative luminance of [c] in 0..1 (sRGB-encoded, Rec. 709 weights).
  static double _luminance(Color c) =>
      0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

  /// Creates a default directional light (sun-like).
  factory Light.directional({
    Vector3? direction,
    Color color = const Color(0xFFFFFFFF),
    double intensity = 1.0,
  }) {
    return Light(
      name: 'directional',
      type: LightType.directional,
      direction: direction ?? Vector3(-0.5, -1, -0.3)
        ..normalize(),
      color: color,
      intensity: intensity,
    );
  }

  /// Creates a point light.
  factory Light.point({
    Vector3? position,
    Color color = const Color(0xFFFFFFFF),
    double intensity = 1.0,
    double range = 10,
  }) {
    final light = Light(
      name: 'point',
      type: LightType.point,
      color: color,
      intensity: intensity,
      range: range,
    );
    if (position != null) light.transform.position = position;
    return light;
  }

  /// Calculates the light contribution at a given surface point and normal.
  double calculateIntensity(Vector3 surfacePoint, Vector3 surfaceNormal) {
    switch (type) {
      case LightType.ambient:
        final ground = groundColor;
        if (ground == null) return intensity;
        // Hemisphere blend on the scalar path: scale by the ground/sky
        // luminance ratio for downward normals, full intensity upward.
        final skyLum = _luminance(color);
        final groundRatio = skyLum > 1e-6 ? _luminance(ground) / skyLum : 1.0;
        final up = (surfaceNormal.y.clamp(-1.0, 1.0) + 1.0) * 0.5;
        return intensity * (groundRatio + (1.0 - groundRatio) * up);

      case LightType.directional:
        final nDotL = surfaceNormal.dot(-direction);
        return (nDotL * intensity).clamp(0.0, 1.0);

      case LightType.point:
        final lightPos = worldPosition;
        final toLight = lightPos - surfacePoint;
        final dist = toLight.length;
        if (range > 0 && dist > range) return 0;

        toLight.normalize();
        final nDotL = surfaceNormal.dot(toLight);
        final attenuation = range > 0
            ? (1 - (dist / range)).clamp(0.0, 1.0)
            : 1 / (1 + dist * dist);
        return (nDotL * intensity * attenuation).clamp(0.0, 1.0);

      case LightType.spot:
        final lightPos = worldPosition;
        final toLight = (lightPos - surfacePoint)..normalize();
        final spotCos = toLight.dot(-direction);
        if (spotCos < (1 - spotAngle)) return 0;
        final nDotL = surfaceNormal.dot(toLight);
        return (nDotL * intensity * spotCos).clamp(0.0, 1.0);
    }
  }
}
