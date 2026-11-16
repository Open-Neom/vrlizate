import 'dart:math' as math;

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

    // Normalize planes in-place without intermediate Vector3/Vector4 allocations.
    for (var i = 0; i < planes.length; i++) {
      final p = planes[i];
      final len2 = p.x * p.x + p.y * p.y + p.z * p.z;
      if (len2 > 0) {
        p.scale(1.0 / math.sqrt(len2));
      }
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

  /// Tests an AABB against the frustum with zero heap allocations.
  CullResult testAabb(Aabb aabb) {
    var allInside = true;
    final minX = aabb.min.x;
    final minY = aabb.min.y;
    final minZ = aabb.min.z;
    final maxX = aabb.max.x;
    final maxY = aabb.max.y;
    final maxZ = aabb.max.z;

    for (var i = 0; i < planes.length; i++) {
      final plane = planes[i];
      final px = plane.x;
      final py = plane.y;
      final pz = plane.z;
      final pw = plane.w;

      final posX = px >= 0 ? maxX : minX;
      final posY = py >= 0 ? maxY : minY;
      final posZ = pz >= 0 ? maxZ : minZ;
      final pDist = px * posX + py * posY + pz * posZ + pw;
      if (pDist < 0) return CullResult.outside; // Entirely outside

      final negX = px >= 0 ? minX : maxX;
      final negY = py >= 0 ? minY : maxY;
      final negZ = pz >= 0 ? minZ : maxZ;
      final nDist = px * negX + py * negY + pz * negZ + pw;
      if (nDist < 0) allInside = false; // Partially inside
    }

    return allInside ? CullResult.inside : CullResult.intersecting;
  }
}
