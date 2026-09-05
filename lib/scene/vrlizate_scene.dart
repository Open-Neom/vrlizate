import 'dart:ui';

import '../effects/hybrid_ray_tracer.dart';
import 'scene.dart';

/// Hardware-aware scene quality for the modern VRlizate scene graph.
enum VrlizateSceneQuality { lite, standard, high }

/// Lighting ray-query strategy.
enum VrlizateRayTracingMode { disabled, hybridObjectSpace }

/// High-quality scene graph used by VRlizate experiences.
///
/// Unlike the legacy particle-based `VRScene`, this scene contains full mesh
/// nodes, materials, lights, spatial UI, culling, and optional bounded hybrid
/// ray queries suitable for smartphones.
class VrlizateScene extends Scene {
  VrlizateSceneQuality quality;
  VrlizateRayTracingMode rayTracingMode;
  int maxRayQueriesPerFrame;
  double rayTracingDistance;
  double shadowVisibility;
  final HybridRayTracer rayTracer;

  int _frameRevision = 0;
  int get frameRevision => _frameRevision;

  VrlizateScene({
    this.quality = VrlizateSceneQuality.standard,
    this.rayTracingMode = VrlizateRayTracingMode.hybridObjectSpace,
    int? maxRayQueriesPerFrame,
    this.rayTracingDistance = 24,
    this.shadowVisibility = 0.38,
    HybridRayTracer? rayTracer,
    super.backgroundColor = const Color(0xFF07111F),
    super.ambientColor = const Color(0xFF202A3A),
    super.fogDensity = 0,
    super.fogColor = const Color(0xFF000000),
  }) : maxRayQueriesPerFrame =
           maxRayQueriesPerFrame ?? _defaultRayBudget(quality),
       rayTracer = rayTracer ?? HybridRayTracer();

  static int _defaultRayBudget(VrlizateSceneQuality quality) =>
      switch (quality) {
        VrlizateSceneQuality.lite => 0,
        VrlizateSceneQuality.standard => 18,
        VrlizateSceneQuality.high => 36,
      };

  int get recommendedSphereSegments => switch (quality) {
    VrlizateSceneQuality.lite => 10,
    VrlizateSceneQuality.standard => 16,
    VrlizateSceneQuality.high => 24,
  };

  @override
  void update(double dt) {
    _frameRevision++;
    super.update(dt);
  }

  @override
  void clear() {
    _frameRevision++;
    super.clear();
  }
}
