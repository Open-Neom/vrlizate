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
      result.expandToInclude(transformed);
    }
    return result;
  }
}
