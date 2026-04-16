import 'package:vector_math/vector_math.dart';

import '../core/math/aabb.dart';

enum CullResult { inside, outside, intersecting }

/// View frustum defined by 6 planes. Used for culling objects outside the camera view.
class VrFrustum {
  /// Planes: left, right, bottom, top, near, far.
  /// Each plane as Vector4(a, b, c, d) where ax + by + cz + d = 0.
  final List<Vector4> planes;

  VrFrustum._(this.planes);

  /// Extracts frustum planes from a view-projection matrix.
  factory VrFrustum.fromViewProjection(Matrix4 vp) {
    final m = vp.storage;
    final planes = <Vector4>[
      // Left:   row3 + row0
      Vector4(m[3] + m[0], m[7] + m[4], m[11] + m[8], m[15] + m[12]),
      // Right:  row3 - row0
      Vector4(m[3] - m[0], m[7] - m[4], m[11] - m[8], m[15] - m[12]),
      // Bottom: row3 + row1
      Vector4(m[3] + m[1], m[7] + m[5], m[11] + m[9], m[15] + m[13]),
      // Top:    row3 - row1
      Vector4(m[3] - m[1], m[7] - m[5], m[11] - m[9], m[15] - m[13]),
      // Near:   row3 + row2
      Vector4(m[3] + m[2], m[7] + m[6], m[11] + m[10], m[15] + m[14]),
      // Far:    row3 - row2
      Vector4(m[3] - m[2], m[7] - m[6], m[11] - m[10], m[15] - m[14]),
    ];

    // Normalize planes
    for (var i = 0; i < planes.length; i++) {
      final p = planes[i];
      final len = Vector3(p.x, p.y, p.z).length;
      if (len > 0) planes[i] = p / len;
    }

    return VrFrustum._(planes);
  }

  /// Tests if a point is inside the frustum.
  bool containsPoint(Vector3 point) {
    for (final plane in planes) {
      final dist =
          plane.x * point.x + plane.y * point.y + plane.z * point.z + plane.w;
      if (dist < 0) return false;
    }
    return true;
  }

  /// Tests an AABB against the frustum.
  CullResult testAabb(Aabb aabb) {
    bool allInside = true;

    for (final plane in planes) {
      // Find the positive vertex (furthest along plane normal)
      final pVertex = Vector3(
        plane.x >= 0 ? aabb.max.x : aabb.min.x,
        plane.y >= 0 ? aabb.max.y : aabb.min.y,
        plane.z >= 0 ? aabb.max.z : aabb.min.z,
      );

      // Find the negative vertex (closest along plane normal)
      final nVertex = Vector3(
        plane.x >= 0 ? aabb.min.x : aabb.max.x,
        plane.y >= 0 ? aabb.min.y : aabb.max.y,
        plane.z >= 0 ? aabb.min.z : aabb.max.z,
      );

      final pDist =
          plane.x * pVertex.x +
          plane.y * pVertex.y +
          plane.z * pVertex.z +
          plane.w;
      final nDist =
          plane.x * nVertex.x +
          plane.y * nVertex.y +
          plane.z * nVertex.z +
          plane.w;

      if (pDist < 0) return CullResult.outside; // Entirely outside
      if (nDist < 0) allInside = false; // Partially inside
    }

    return allInside ? CullResult.inside : CullResult.intersecting;
  }
}
