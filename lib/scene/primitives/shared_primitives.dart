import 'package:vector_math/vector_math.dart';

import '../geometry.dart';
import 'cube_geometry.dart';
import 'cylinder_geometry.dart';
import 'plane_geometry.dart';
import 'sphere_geometry.dart';

/// Process-wide, immutable unit primitives for retained GPU rendering.
///
/// Retained renderers cache GPU buffers by [Geometry] *identity*, so every
/// `CubeGeometry()` call becomes a separate vertex/index upload even when the
/// vertex data is identical. Scale the shared unit primitive through the
/// node transform instead: a hangar built from `SharedPrimitives.unitCube`
/// uploads one cube for all of its walls, pillars, doors and consoles.
///
/// The instances are shared and must never be mutated. Geometry arrays are
/// already treated as immutable by the retained adapter; this class simply
/// gives every caller the same instance.
abstract final class SharedPrimitives {
  /// 1 m cube centered on the origin (24 vertices, 12 triangles).
  static final CubeGeometry unitCube = CubeGeometry(size: 1.0);

  /// 1 m × 1 m horizontal quad centered on the origin, facing +Y.
  static final PlaneGeometry unitPlane = PlaneGeometry(width: 1.0, height: 1.0);

  /// Sphere of diameter 1 m, 16 segments (smooth, ~290 vertices).
  static final SphereGeometry unitSphere = SphereGeometry(
    radius: 0.5,
    segments: 16,
  );

  /// Sphere of diameter 1 m, 8 segments (coarse, for projectiles and gems).
  static final SphereGeometry unitSphereCoarse = SphereGeometry(
    radius: 0.5,
    segments: 8,
  );

  /// Cylinder of diameter 1 m and height 1 m along Y, 16 segments.
  static final CylinderGeometry unitCylinder = CylinderGeometry(
    radius: 0.5,
    height: 1.0,
    segments: 16,
  );

  /// Cylinder of diameter 1 m and height 1 m along Y, 8 segments (posts,
  /// torch handles, thin trims where silhouette smoothness is not visible).
  static final CylinderGeometry unitCylinderCoarse = CylinderGeometry(
    radius: 0.5,
    height: 1.0,
    segments: 8,
  );

  /// Sphere of diameter 1 m, 32 segments (~1 100 vertices): for hero objects
  /// larger than ~0.5 m whose silhouette the viewer inspects up close.
  static final SphereGeometry unitSphereFine = SphereGeometry(
    radius: 0.5,
    segments: 32,
  );

  /// Cylinder of diameter 1 m and height 1 m along Y, 32 segments: for
  /// large columns, drums and discs seen from arm's length.
  static final CylinderGeometry unitCylinderFine = CylinderGeometry(
    radius: 0.5,
    height: 1.0,
    segments: 32,
  );

  /// Convenience scale vector for a cuboid of the given extents.
  static Vector3 cuboidScale(double width, double height, double depth) =>
      Vector3(width, height, depth);
}
