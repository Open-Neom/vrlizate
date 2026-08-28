import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:vector_math/vector_math.dart';

import '../camera/camera_rig.dart';
import '../../interaction/raycast.dart';

/// Gaze-based pointer for VR interaction (look to select).
/// Fires a ray from the camera center forward direction.
///
/// Supports adaptive dwell timing (repeated selections of the same target
/// become faster), a grace period that tolerates brief gaze slips, tactile
/// haptic feedback on selection, and a richer reticle with progress feedback states.
class GazePointer {
  final CameraRig cameraRig;

  /// Duration in seconds to dwell-select a fresh target.
  double dwellDuration;

  /// Minimum dwell duration when [adaptiveDwell] accelerates repeated
  /// selections of the same target.
  double minDwellDuration;

  /// Dwell acceleration factor applied each time the same target is
  /// dwell-selected consecutively (0.8 = 20% faster each time).
  double dwellAcceleration;

  /// Whether repeated selections of the same target shrink the dwell time.
  bool adaptiveDwell;

  /// Grace period in seconds: if the gaze briefly leaves the target for less
  /// than this, the dwell timer is preserved instead of reset.
  double gazeGracePeriod;

  /// Whether to trigger subtle tactile haptic feedback on gaze enter and dwell selection.
  bool enableHaptics;

  /// Current dwell progress (0 to 1).
  double dwellProgress = 0;

  /// The effective dwell duration currently in use (after adaptation).
  double get effectiveDwellDuration => _effectiveDwell;
  double _effectiveDwell;

  /// ID of the node currently being gazed at.
  String? get gazeTargetId => _gazeTargetId;
  String? _gazeTargetId;
  double _gazeTimer = 0;
  bool _selected = false;

  // Adaptive dwell state
  String? _lastSelectedId;

  // Grace period state
  String? _graceTargetId;
  double _graceTimer = 0;
  double _graceSavedGazeTimer = 0;

  /// Callback when a target is selected via dwell.
  void Function(String nodeId)? onDwellSelect;

  /// Alias for [onDwellSelect].
  void Function(String nodeId)? get onGazeSelect => onDwellSelect;
  set onGazeSelect(void Function(String nodeId)? fn) => onDwellSelect = fn;

  /// Callback when a target is tapped/clicked.
  void Function(String nodeId)? onTap;

  /// Callback when gaze enters a target.
  void Function(String nodeId)? onGazeEnter;

  /// Callback when gaze exits a target.
  void Function(String nodeId)? onGazeExit;

  /// Callback with dwell progress updates (nodeId, progress 0..1).
  void Function(String nodeId, double progress)? onDwellProgress;

  GazePointer({
    required this.cameraRig,
    this.dwellDuration = 2.0,
    this.minDwellDuration = 0.6,
    this.dwellAcceleration = 0.8,
    this.adaptiveDwell = true,
    this.gazeGracePeriod = 0.15,
    this.enableHaptics = true,
    this.onDwellSelect,
    this.onTap,
    this.onGazeEnter,
    this.onGazeExit,
    this.onDwellProgress,
  }) : _effectiveDwell = dwellDuration;

  /// Manually trigger a tap/click event on the currently gazed target.
  void triggerTap(RaycastHit? hit) {
    if (_gazeTargetId != null) {
      if (enableHaptics) {
        HapticFeedback.mediumImpact();
      }
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

  /// Resets adaptive dwell acceleration (e.g. when the scene changes).
  void resetAdaptation() {
    _lastSelectedId = null;
    _effectiveDwell = dwellDuration;
  }

  /// Call each frame with the currently gazed node ID (or null).
  void update(double dt, String? hitNodeId) {
    // Grace period: brief loss of the target preserves the dwell timer.
    if (hitNodeId == null && _gazeTargetId != null && !_selected) {
      if (_graceTargetId != _gazeTargetId) {
        _graceTargetId = _gazeTargetId;
        _graceTimer = 0;
        _graceSavedGazeTimer = _gazeTimer;
      }
      _graceTimer += dt;
      if (_graceTimer < gazeGracePeriod) {
        // Hold progress steady during the grace window.
        return;
      }
    }

    if (hitNodeId != _gazeTargetId) {
      // Gaze changed target
      if (_gazeTargetId != null) onGazeExit?.call(_gazeTargetId!);

      // Restoring the same target within the grace window resumes the timer.
      final resumed =
          hitNodeId != null &&
          hitNodeId == _graceTargetId &&
          _graceTimer < gazeGracePeriod;

      _gazeTargetId = hitNodeId;
      _gazeTimer = resumed ? _graceSavedGazeTimer : 0;
      _selected = false;
      dwellProgress = resumed
          ? (_gazeTimer / _effectiveDwell).clamp(0.0, 1.0)
          : 0;
      _graceTargetId = null;
      _graceTimer = 0;
      if (hitNodeId != null) {
        if (enableHaptics) {
          HapticFeedback.selectionClick();
        }
        onGazeEnter?.call(hitNodeId);
      }
      return;
    }

    if (hitNodeId == null) {
      dwellProgress = 0;
      return;
    }

    _graceTargetId = null;
    _graceTimer = 0;

    _gazeTimer += dt;
    dwellProgress = (_gazeTimer / _effectiveDwell).clamp(0.0, 1.0);
    onDwellProgress?.call(hitNodeId, dwellProgress);

    if (dwellProgress >= 1.0 && !_selected) {
      _selected = true;
      _applyAdaptation(hitNodeId);
      if (enableHaptics) {
        HapticFeedback.lightImpact();
      }
      onDwellSelect?.call(hitNodeId);
    }
  }

  void _applyAdaptation(String nodeId) {
    if (!adaptiveDwell) return;
    if (_lastSelectedId == nodeId) {
      _effectiveDwell = (_effectiveDwell * dwellAcceleration).clamp(
        minDwellDuration,
        dwellDuration,
      );
    } else {
      _lastSelectedId = nodeId;
      _effectiveDwell = dwellDuration;
    }
  }

  /// Renders the reticle (crosshair) at screen center with dwell feedback:
  /// an accent progress ring, tick marks, and a selection flash.
  void renderReticle(Canvas canvas, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    const baseRadius = 4.0;
    final dwellRadius = baseRadius + dwellProgress * 8;
    final hasTarget = _gazeTargetId != null;

    // Outer ring (dwell progress) with color ramp white -> accent.
    if (dwellProgress > 0) {
      final ringColor = Color.lerp(
        const Color(0xFFFFFFFF),
        const Color(0xFF2E90FA),
        dwellProgress,
      )!;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: dwellRadius),
        -1.5708, // Start at top
        dwellProgress * 6.2832, // Full circle
        false,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      // Tick marks at quarter positions for readable progress.
      final tickPaint = Paint()
        ..color = ringColor.withValues(alpha: 0.7)
        ..strokeWidth = 1.5;
      for (var i = 0; i < 4; i++) {
        final angle = -1.5708 + i * 1.5708;
        final inner = Offset(
          center.dx + (dwellRadius - 3) * math.cos(angle),
          center.dy + (dwellRadius - 3) * math.sin(angle),
        );
        final outer = Offset(
          center.dx + (dwellRadius + 3) * math.cos(angle),
          center.dy + (dwellRadius + 3) * math.sin(angle),
        );
        canvas.drawLine(inner, outer, tickPaint);
      }
    }

    // Selection flash: expanding ring fading out right after dwell-select.
    if (_selected) {
      canvas.drawCircle(
        center,
        dwellRadius + 4,
        Paint()
          ..color = const Color(0x662E90FA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // Hover halo when a target is gazed but dwell has not started.
    if (hasTarget && dwellProgress == 0) {
      canvas.drawCircle(
        center,
        baseRadius + 4,
        Paint()
          ..color = const Color(0x40FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Center dot
    canvas.drawCircle(
      center,
      hasTarget ? 3 : 2,
      Paint()..color = const Color(0xCCFFFFFF),
    );
  }
}
