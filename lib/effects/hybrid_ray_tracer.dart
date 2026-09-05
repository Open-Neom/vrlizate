import 'package:vector_math/vector_math.dart';

import '../core/math/aabb.dart';
import '../scene/light.dart';
import '../scene/mesh.dart';

/// Result of a low-cost world-space ray query.
class HybridRayHit {
  final MeshNode node;
  final double distance;
  final Vector3 point;

  const HybridRayHit({
    required this.node,
    required this.distance,
    required this.point,
  });
}

/// CPU ray queries designed for hybrid lighting on mobile devices.
///
/// This is deliberately not a per-pixel path tracer. It traces against mesh
/// world AABBs and supplies object-level light visibility to the rasterizer.
/// The result is stable stereo lighting at a bounded CPU cost.
class HybridRayTracer {
  static const double _epsilon = 1e-6;

  int raysCast = 0;
  int hits = 0;

  void resetStats() {
    raysCast = 0;
    hits = 0;
  }

  HybridRayHit? traceClosest({
    required Vector3 origin,
    required Vector3 direction,
    required Iterable<MeshNode> nodes,
    MeshNode? ignore,
    double maxDistance = 30,
  }) {
    if (direction.length2 <= _epsilon || maxDistance <= 0) return null;

    raysCast++;
    final rayDirection = direction.normalized();
    MeshNode? nearestNode;
    var nearestDistance = maxDistance;

    for (final node in nodes) {
      if (!node.visible || identical(node, ignore)) continue;
      final distance = _intersectAabb(
        origin,
        rayDirection,
        node.worldAabb,
        nearestDistance,
      );
      if (distance != null && distance < nearestDistance) {
        nearestNode = node;
        nearestDistance = distance;
      }
    }

    if (nearestNode == null) return null;
    hits++;
    return HybridRayHit(
      node: nearestNode,
      distance: nearestDistance,
      point: origin + rayDirection * nearestDistance,
    );
  }

  /// Returns direct-light visibility for [receiver] in the range 0..1.
  ///
  /// Ambient lighting remains rasterized normally. Directional and point
  /// lights use a single conservative ray from the receiver bounds toward
  /// the light. [shadowVisibility] keeps occluded objects readable in VR.
  double lightVisibility({
    required LitMeshNode receiver,
    required Light light,
    required Iterable<MeshNode> nodes,
    double maxDistance = 30,
    double shadowVisibility = 0.32,
  }) {
    if (light.type == LightType.ambient || light.type == LightType.spot) {
      return 1;
    }

    final bounds = receiver.worldAabb;
    final center = bounds.center;
    late final Vector3 direction;
    late final double rayLength;

    if (light.type == LightType.directional) {
      direction = -light.direction;
      rayLength = maxDistance;
    } else {
      final toLight = light.worldPosition - center;
      rayLength = toLight.length.clamp(0.0, maxDistance);
      if (rayLength <= _epsilon) return 1;
      direction = toLight / toLight.length;
    }

    direction.normalize();
    final extents = bounds.extents;
    final projectedRadius =
        direction.x.abs() * extents.x +
        direction.y.abs() * extents.y +
        direction.z.abs() * extents.z;
    final origin = center + direction * (projectedRadius + 0.01);
    final hit = traceClosest(
      origin: origin,
      direction: direction,
      nodes: nodes,
      ignore: receiver,
      maxDistance: rayLength,
    );
    return hit == null ? 1 : shadowVisibility.clamp(0.0, 1.0);
  }

  double? _intersectAabb(
    Vector3 origin,
    Vector3 direction,
    Aabb bounds,
    double maxDistance,
  ) {
    var enter = 0.0;
    var exit = maxDistance;

    bool testAxis(double o, double d, double min, double max) {
      if (d.abs() < _epsilon) return o >= min && o <= max;
      var t0 = (min - o) / d;
      var t1 = (max - o) / d;
      if (t0 > t1) {
        final swap = t0;
        t0 = t1;
        t1 = swap;
      }
      if (t0 > enter) enter = t0;
      if (t1 < exit) exit = t1;
      return enter <= exit;
    }

    if (!testAxis(origin.x, direction.x, bounds.min.x, bounds.max.x) ||
        !testAxis(origin.y, direction.y, bounds.min.y, bounds.max.y) ||
        !testAxis(origin.z, direction.z, bounds.min.z, bounds.max.z)) {
      return null;
    }
    if (exit < 0 || enter > maxDistance) return null;
    return enter >= 0 ? enter : exit;
  }
}
