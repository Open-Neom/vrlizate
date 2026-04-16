import 'dart:ui';

import '../../utils/vr_math.dart';
import '../camera/vr_camera.dart';

/// Projected 2D point with depth info for z-sorting.
class ProjectedPoint {
  final double screenX;
  final double screenY;
  final double depth;
  final bool visible;

  const ProjectedPoint({
    required this.screenX,
    required this.screenY,
    required this.depth,
    this.visible = true,
  });

  Offset get offset => Offset(screenX, screenY);
}

/// Stereoscopic projection engine.
/// Projects 3D points to left/right eye viewports.
class StereoscopicProjection {
  /// Inter-pupillary distance in meters (default: average human 0.065m).
  double eyeSeparation;

  /// Scale factor for perspective projection.
  double projectionScale;

  StereoscopicProjection({
    this.eyeSeparation = 0.065,
    this.projectionScale = 300,
  });

  /// Projects a 3D point to the LEFT eye viewport.
  ProjectedPoint projectLeft(
    Offset3D point,
    VRCamera camera,
    double viewportWidth,
    double viewportHeight,
  ) {
    return _project(
      point,
      camera,
      -eyeSeparation / 2,
      viewportWidth,
      viewportHeight,
    );
  }

  /// Projects a 3D point to the RIGHT eye viewport.
  ProjectedPoint projectRight(
    Offset3D point,
    VRCamera camera,
    double viewportWidth,
    double viewportHeight,
  ) {
    return _project(
      point,
      camera,
      eyeSeparation / 2,
      viewportWidth,
      viewportHeight,
    );
  }

  /// Projects a 3D point for a SINGLE eye (monoscopic).
  ProjectedPoint projectMono(
    Offset3D point,
    VRCamera camera,
    double viewportWidth,
    double viewportHeight,
  ) {
    return _project(point, camera, 0, viewportWidth, viewportHeight);
  }

  ProjectedPoint _project(
    Offset3D point,
    VRCamera camera,
    double eyeOffset,
    double viewportWidth,
    double viewportHeight,
  ) {
    // Apply eye offset
    final shifted = Offset3D(point.x, point.y + eyeOffset, point.z);

    // Transform to camera space
    final rotated = camera.worldToCamera(shifted);

    // Behind camera check
    if (rotated.x <= 0.1) {
      return const ProjectedPoint(
        screenX: 0,
        screenY: 0,
        depth: 0,
        visible: false,
      );
    }

    // Perspective divide
    final scale = projectionScale / rotated.x;
    final screenX = viewportWidth / 2 + rotated.y * scale;
    final screenY = viewportHeight / 2 - rotated.z * scale;

    // Bounds check with margin
    const margin = 50.0;
    final visible =
        screenX >= -margin &&
        screenX <= viewportWidth + margin &&
        screenY >= -margin &&
        screenY <= viewportHeight + margin;

    return ProjectedPoint(
      screenX: screenX,
      screenY: screenY,
      depth: rotated.x,
      visible: visible,
    );
  }
}
