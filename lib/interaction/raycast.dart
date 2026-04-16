import 'package:vector_math/vector_math.dart';

import '../core/math/aabb.dart';
import '../scene/node.dart';

/// Result of a raycast hit.
class RaycastHit {
  final Node node;
  final Vector3 point;
  final double distance;
  final Vector3 normal;

  const RaycastHit({
    required this.node,
    required this.point,
    required this.distance,
    required this.normal,
  });
}

/// Raycaster for testing ray-mesh intersections in the scene.
class Raycaster {
  /// Casts a ray against all visible nodes in the tree.
  /// Returns hits sorted by distance (nearest first).
  List<RaycastHit> cast(Ray ray, Node root, {double maxDistance = 1000}) {
    final hits = <RaycastHit>[];
    _castRecursive(ray, root, hits, maxDistance);
    hits.sort((a, b) => a.distance.compareTo(b.distance));
    return hits;
  }

  /// Returns the nearest hit, or null.
  RaycastHit? castNearest(Ray ray, Node root, {double maxDistance = 1000}) {
    final hits = cast(ray, root, maxDistance: maxDistance);
    return hits.isNotEmpty ? hits.first : null;
  }

  void _castRecursive(
    Ray ray,
    Node node,
    List<RaycastHit> hits,
    double maxDist,
  ) {
    if (!node.visible) return;

    // Quick AABB test first
    final aabb = node.worldAabb;
    if (!_rayIntersectsAabb(ray, aabb, maxDist)) {
      // Also skip children if parent AABB missed
      return;
    }

    // Test this node's AABB as a hit (approximation for non-mesh nodes)
    final aabbHit = _rayAabbIntersection(ray, aabb);
    if (aabbHit != null && aabbHit <= maxDist) {
      hits.add(
        RaycastHit(
          node: node,
          point: ray.at(aabbHit),
          distance: aabbHit,
          normal: _estimateNormal(ray.at(aabbHit), aabb),
        ),
      );
    }

    for (final child in node.children) {
      _castRecursive(ray, child, hits, maxDist);
    }
  }

  bool _rayIntersectsAabb(Ray ray, Aabb aabb, double maxDist) {
    final t = _rayAabbIntersection(ray, aabb);
    return t != null && t <= maxDist;
  }

  /// Slab method for ray-AABB intersection. Returns distance or null.
  double? _rayAabbIntersection(Ray ray, Aabb aabb) {
    final invDir = Vector3(
      ray.direction.x != 0 ? 1 / ray.direction.x : double.infinity,
      ray.direction.y != 0 ? 1 / ray.direction.y : double.infinity,
      ray.direction.z != 0 ? 1 / ray.direction.z : double.infinity,
    );

    final t1 = (aabb.min.x - ray.origin.x) * invDir.x;
    final t2 = (aabb.max.x - ray.origin.x) * invDir.x;
    final t3 = (aabb.min.y - ray.origin.y) * invDir.y;
    final t4 = (aabb.max.y - ray.origin.y) * invDir.y;
    final t5 = (aabb.min.z - ray.origin.z) * invDir.z;
    final t6 = (aabb.max.z - ray.origin.z) * invDir.z;

    final tMin = [t1, t2].reduce((a, b) => a < b ? a : b);
    final tMax = [t1, t2].reduce((a, b) => a > b ? a : b);
    final tyMin = [t3, t4].reduce((a, b) => a < b ? a : b);
    final tyMax = [t3, t4].reduce((a, b) => a > b ? a : b);

    double enterT = tMin > tyMin ? tMin : tyMin;
    double exitT = tMax < tyMax ? tMax : tyMax;

    if (enterT > exitT) return null;

    final tzMin = [t5, t6].reduce((a, b) => a < b ? a : b);
    final tzMax = [t5, t6].reduce((a, b) => a > b ? a : b);

    enterT = enterT > tzMin ? enterT : tzMin;
    exitT = exitT < tzMax ? exitT : tzMax;

    if (enterT > exitT || exitT < 0) return null;
    return enterT > 0 ? enterT : exitT;
  }

  Vector3 _estimateNormal(Vector3 point, Aabb aabb) {
    final center = aabb.center;
    final diff = point - center;
    final ext = aabb.extents;

    // Find which face is closest
    final ax = (diff.x / ext.x).abs();
    final ay = (diff.y / ext.y).abs();
    final az = (diff.z / ext.z).abs();

    if (ax > ay && ax > az) return Vector3(diff.x > 0 ? 1 : -1, 0, 0);
    if (ay > az) return Vector3(0, diff.y > 0 ? 1 : -1, 0);
    return Vector3(0, 0, diff.z > 0 ? 1 : -1);
  }
}
