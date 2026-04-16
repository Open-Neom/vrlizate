import 'dart:ui';

import 'material.dart';
import 'texture.dart';

/// Physically-Based Rendering material with texture maps.
/// Inspired by Thermion/Filament PBR and three_js MeshStandardMaterial.
class PBRMaterial extends VRMaterial {
  /// Base color texture (albedo map).
  VRTexture? colorMap;

  /// Normal map for surface detail without extra geometry.
  VRTexture? normalMap;
  double normalScale;

  /// Metallic-roughness map (R=metallic, G=roughness).
  VRTexture? metallicRoughnessMap;

  /// Emission map (self-illumination).
  VRTexture? emissionMap;
  double emissionIntensity;

  /// Ambient occlusion map.
  VRTexture? aoMap;
  double aoIntensity;

  /// Environment map for reflections (IBL).
  VRTexture? envMap;
  double envMapIntensity;

  /// Alpha map for transparency.
  VRTexture? alphaMap;

  PBRMaterial({
    super.color = const Color(0xFFCCCCCC),
    super.emissive = const Color(0xFF000000),
    super.opacity = 1.0,
    super.metallic = 0.0,
    super.roughness = 0.8,
    super.doubleSided = false,
    super.wireframe = false,
    this.colorMap,
    this.normalMap,
    this.normalScale = 1.0,
    this.metallicRoughnessMap,
    this.emissionMap,
    this.emissionIntensity = 1.0,
    this.aoMap,
    this.aoIntensity = 1.0,
    this.envMap,
    this.envMapIntensity = 1.0,
    this.alphaMap,
  });

  bool get hasColorMap => colorMap?.isLoaded ?? false;
  bool get hasNormalMap => normalMap?.isLoaded ?? false;
  bool get hasEmissionMap => emissionMap?.isLoaded ?? false;
  bool get hasEnvMap => envMap?.isLoaded ?? false;

  /// Computes the final color at a surface point using PBR.
  /// Simplified Cook-Torrance BRDF for Canvas rendering.
  Color computeColor({
    required double nDotL,
    required double nDotV,
    required double nDotH,
    Color lightColor = const Color(0xFFFFFFFF),
    double lightIntensity = 1.0,
  }) {
    // Fresnel (Schlick approximation)
    final f0 = metallic > 0.5 ? 0.95 : 0.04;
    final fresnel = f0 + (1 - f0) * _pow5(1 - nDotV);

    // Distribution (GGX/Trowbridge-Reitz)
    final a = roughness * roughness;
    final a2 = a * a;
    final denom = nDotH * nDotH * (a2 - 1) + 1;
    final distribution = a2 / (3.14159 * denom * denom + 0.0001);

    // Geometry (Smith GGX)
    final k = (roughness + 1) * (roughness + 1) / 8;
    final gv = nDotV / (nDotV * (1 - k) + k + 0.0001);
    final gl = nDotL / (nDotL * (1 - k) + k + 0.0001);
    final geometry = gv * gl;

    // Specular
    final specular =
        (distribution * fresnel * geometry) / (4 * nDotV * nDotL + 0.0001);

    // Diffuse (Lambertian)
    final diffuse = (1 - fresnel) * (1 - metallic) / 3.14159;

    // Combine
    final factor = (diffuse + specular) * nDotL * lightIntensity;

    final r =
        ((color.r * 255.0).round().clamp(0, 255) * factor +
                (emissive.r * 255.0).round().clamp(0, 255) * emissionIntensity)
            .clamp(0, 255)
            .toInt();
    final g =
        ((color.g * 255.0).round().clamp(0, 255) * factor +
                (emissive.g * 255.0).round().clamp(0, 255) * emissionIntensity)
            .clamp(0, 255)
            .toInt();
    final b =
        ((color.b * 255.0).round().clamp(0, 255) * factor +
                (emissive.b * 255.0).round().clamp(0, 255) * emissionIntensity)
            .clamp(0, 255)
            .toInt();

    return Color.fromARGB((opacity * 255).toInt(), r, g, b);
  }

  double _pow5(double x) => x * x * x * x * x;

  void dispose() {
    colorMap?.dispose();
    normalMap?.dispose();
    metallicRoughnessMap?.dispose();
    emissionMap?.dispose();
    aoMap?.dispose();
    envMap?.dispose();
    alphaMap?.dispose();
  }
}
