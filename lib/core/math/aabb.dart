import 'package:vector_math/vector_math.dart';

/// Axis-aligned bounding box for frustum culling.
class Aabb {
  Vector3 min;
  Vector3 max;

  Aabb({Vector3? min, Vector3? max})
    : min = min ?? Vector3(double.infinity, double.infinity, double.infinity),
      max =
          max ??
          Vector3(
            double.negativeInfinity,
            double.negativeInfinity,
            double.negativeInfinity,
          );

  Aabb.fromCenterExtents(Vector3 center, Vector3 extents)
    : min = center - extents,
      max = center + extents;

  Vector3 get center => (min + max) * 0.5;
  Vector3 get extents => (max - min) * 0.5;
  Vector3 get size => max - min;

  void expandToInclude(Vector3 point) {
    min = Vector3(
      point.x < min.x ? point.x : min.x,
      point.y < min.y ? point.y : min.y,
      point.z < min.z ? point.z : min.z,
    );
    max = Vector3(
      point.x > max.x ? point.x : max.x,
      point.y > max.y ? point.y : max.y,
      point.z > max.z ? point.z : max.z,
    );
  }

  void expandToIncludeAabb(Aabb other) {
    expandToInclude(other.min);
    expandToInclude(other.max);
  }

  bool containsPoint(Vector3 point) {
    return point.x >= min.x &&
        point.x <= max.x &&
        point.y >= min.y &&
        point.y <= max.y &&
        point.z >= min.z &&
        point.z <= max.z;
  }

  bool intersectsAabb(Aabb other) {
    return min.x <= other.max.x &&
        max.x >= other.min.x &&
        min.y <= other.max.y &&
        max.y >= other.min.y &&
        min.z <= other.max.z &&
        max.z >= other.min.z;
  }

  /// Transforms this AABB by a matrix, producing a new AABB that encloses the result.
  Aabb transformed(Matrix4 matrix) {
    final corners = [
      Vector3(min.x, min.y, min.z),
      Vector3(max.x, min.y, min.z),
      Vector3(min.x, max.y, min.z),
      Vector3(max.x, max.y, min.z),
      Vector3(min.x, min.y, max.z),
      Vector3(max.x, min.y, max.z),
      Vector3(min.x, max.y, max.z),
      Vector3(max.x, max.y, max.z),
    ];

    final result = Aabb();
    for (final corner in corners) {
      final transformed = matrix.transformed3(corner);
      // This result is private until return. Reuse its bounds while preserving
      // the exact comparisons, Float32 rounding and transformed3 dispatch.
      result.min.setValues(
        transformed.x < result.min.x ? transformed.x : result.min.x,
        transformed.y < result.min.y ? transformed.y : result.min.y,
        transformed.z < result.min.z ? transformed.z : result.min.z,
      );
      result.max.setValues(
        transformed.x > result.max.x ? transformed.x : result.max.x,
        transformed.y > result.max.y ? transformed.y : result.max.y,
        transformed.z > result.max.z ? transformed.z : result.max.z,
      );
    }
    return result;
  }

  /// Zero-allocation affine AABB transform (Jim Arvo, Graphics Gems I, 1990).
  ///
  /// Writes the exact world-space enclosure of `this` under affine [matrix]
  /// (`[R | t]`, assuming perspective row `[0, 0, 0, 1]`) directly into [out]
  /// without allocating intermediate corner [Vector3]s or lists.
  void transformAffineInto(Matrix4 matrix, Aabb out) {
    final minX = min.x;
    final minY = min.y;
    final minZ = min.z;
    final maxX = max.x;
    final maxY = max.y;
    final maxZ = max.z;

    if (minX > maxX || minY > maxY || minZ > maxZ) {
      out.min.setValues(double.infinity, double.infinity, double.infinity);
      out.max.setValues(
        double.negativeInfinity,
        double.negativeInfinity,
        double.negativeInfinity,
      );
      return;
    }

    final s = matrix.storage;
    // Row 0
    var loX = s[12];
    var hiX = loX;
    final a00 = s[0] * minX, b00 = s[0] * maxX;
    if (a00 < b00) {
      loX += a00;
      hiX += b00;
    } else {
      loX += b00;
      hiX += a00;
    }
    final a01 = s[4] * minY, b01 = s[4] * maxY;
    if (a01 < b01) {
      loX += a01;
      hiX += b01;
    } else {
      loX += b01;
      hiX += a01;
    }
    final a02 = s[8] * minZ, b02 = s[8] * maxZ;
    if (a02 < b02) {
      loX += a02;
      hiX += b02;
    } else {
      loX += b02;
      hiX += a02;
    }

    // Row 1
    var loY = s[13];
    var hiY = loY;
    final a10 = s[1] * minX, b10 = s[1] * maxX;
    if (a10 < b10) {
      loY += a10;
      hiY += b10;
    } else {
      loY += b10;
      hiY += a10;
    }
    final a11 = s[5] * minY, b11 = s[5] * maxY;
    if (a11 < b11) {
      loY += a11;
      hiY += b11;
    } else {
      loY += b11;
      hiY += a11;
    }
    final a12 = s[9] * minZ, b12 = s[9] * maxZ;
    if (a12 < b12) {
      loY += a12;
      hiY += b12;
    } else {
      loY += b12;
      hiY += a12;
    }

    // Row 2
    var loZ = s[14];
    var hiZ = loZ;
    final a20 = s[2] * minX, b20 = s[2] * maxX;
    if (a20 < b20) {
      loZ += a20;
      hiZ += b20;
    } else {
      loZ += b20;
      hiZ += a20;
    }
    final a21 = s[6] * minY, b21 = s[6] * maxY;
    if (a21 < b21) {
      loZ += a21;
      hiZ += b21;
    } else {
      loZ += b21;
      hiZ += a21;
    }
    final a22 = s[10] * minZ, b22 = s[10] * maxZ;
    if (a22 < b22) {
      loZ += a22;
      hiZ += b22;
    } else {
      loZ += b22;
      hiZ += a22;
    }

    out.min.setValues(loX, loY, loZ);
    out.max.setValues(hiX, hiY, hiZ);
  }

  /// Expands [min] and [max] in-place to include [other] without allocating
  /// replacement [Vector3] instances. Intended for owned cache boxes.
  void expandBoundsInPlace(Aabb other) {
    final oMin = other.min;
    final oMax = other.max;
    if (oMin.x > oMax.x || oMin.y > oMax.y || oMin.z > oMax.z) return;
    min.setValues(
      oMin.x < min.x ? oMin.x : min.x,
      oMin.y < min.y ? oMin.y : min.y,
      oMin.z < min.z ? oMin.z : min.z,
    );
    max.setValues(
      oMax.x > max.x ? oMax.x : max.x,
      oMax.y > max.y ? oMax.y : max.y,
      oMax.z > max.z ? oMax.z : max.z,
    );
  }
}
