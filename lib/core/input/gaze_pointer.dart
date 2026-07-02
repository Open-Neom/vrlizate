import 'dart:ui';

import 'package:vector_math/vector_math.dart';

import '../camera/camera_rig.dart';
import '../../interaction/raycast.dart';

/// Gaze-based pointer for VR interaction (look to select).
/// Fires a ray from the camera center forward direction.
class GazePointer {
  final CameraRig cameraRig;

  /// Duration in seconds to dwell-select.
  double dwellDuration;

  /// Current dwell progress (0 to 1).
  double dwellProgress = 0;

  /// ID of the node currently being gazed at.
  String? _gazeTargetId;
  double _gazeTimer = 0;
  bool _selected = false;

  /// Callback when a target is selected via dwell.
  void Function(String nodeId)? onDwellSelect;

  /// Callback when a target is tapped/clicked.
  void Function(String nodeId)? onTap;

  /// Callback when gaze enters a target.
  void Function(String nodeId)? onGazeEnter;

  /// Callback when gaze exits a target.
  void Function(String nodeId)? onGazeExit;

  GazePointer({
    required this.cameraRig,
    this.dwellDuration = 2.0,
    this.onDwellSelect,
    this.onTap,
    this.onGazeEnter,
    this.onGazeExit,
  });

  /// Manually trigger a tap/click event on the currently gazed target.
  void triggerTap(RaycastHit? hit) {
    if (_gazeTargetId != null) {
      onTap?.call(_gazeTargetId!);
      onDwellSelect?.call(_gazeTargetId!);
      
      // Trigger Pointable component if registered on the node
      if (hit != null && hit.node.pointable != null) {
        hit.node.pointable!.press(hit);
        Future.delayed(const Duration(milliseconds: 100), () {
          hit.node.pointable?.release();
        });
      }
    }
  }

  /// The ray from camera center in forward direction.
  Ray get ray =>
      Ray.originDirection(cameraRig.position, cameraRig.headTransform.forward);

  /// Call each frame with the currently gazed node ID (or null).
  void update(double dt, String? hitNodeId) {
    if (hitNodeId != _gazeTargetId) {
      // Gaze changed target
      if (_gazeTargetId != null) onGazeExit?.call(_gazeTargetId!);
      _gazeTargetId = hitNodeId;
      _gazeTimer = 0;
      _selected = false;
      dwellProgress = 0;
      if (hitNodeId != null) onGazeEnter?.call(hitNodeId);
      return;
    }

    if (hitNodeId == null) {
      dwellProgress = 0;
      return;
    }

    _gazeTimer += dt;
    dwellProgress = (_gazeTimer / dwellDuration).clamp(0, 1);

    if (dwellProgress >= 1.0 && !_selected) {
      _selected = true;
      onDwellSelect?.call(hitNodeId);
    }
  }

  /// Renders the reticle (crosshair) at screen center.
  void renderReticle(Canvas canvas, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    const baseRadius = 4.0;
    final dwellRadius = baseRadius + dwellProgress * 8;

    // Outer ring (dwell progress)
    if (dwellProgress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: dwellRadius),
        -1.5708, // Start at top
        dwellProgress * 6.2832, // Full circle
        false,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Center dot
    canvas.drawCircle(
      center,
      _gazeTargetId != null ? 3 : 2,
      Paint()..color = const Color(0xCCFFFFFF),
    );
  }
}
