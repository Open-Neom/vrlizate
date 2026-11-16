import 'package:flutter/material.dart';

import '../core/rendering/vr_renderer.dart';
import '../scene/vr_audio_reactive_360_engine.dart';

/// Monoscopic (single-eye) painter for a [VrAudioReactive360Engine] 360° view.
class VrSpatial360Painter extends CustomPainter {
  final VrAudioReactive360Engine engine;
  final bool showRings;
  final bool showConstellations;
  final bool showNebula;

  late final VRMonoPainter _monoPainter;

  VrSpatial360Painter({
    required this.engine,
    this.showRings = true,
    this.showConstellations = true,
    this.showNebula = true,
  }) {
    for (final r in engine.rings) {
      r.vrElement.visible = showRings;
    }
    for (final c in engine.constellations) {
      c.vrElement.visible = showConstellations;
    }

    _monoPainter = VRMonoPainter(
      renderer: engine.scene,
      camera: engine.camera,
      projection: engine.projection,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _monoPainter.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant VrSpatial360Painter oldDelegate) => true;
}

/// Side-by-side stereoscopic painter for a [VrAudioReactive360Engine] 360° view.
class VrStereo360Painter extends CustomPainter {
  final VrAudioReactive360Engine engine;
  final bool showRings;
  final bool showConstellations;
  final bool showNebula;

  late final VRStereoPainter _stereoPainter;

  VrStereo360Painter({
    required this.engine,
    this.showRings = true,
    this.showConstellations = true,
    this.showNebula = true,
  }) {
    for (final r in engine.rings) {
      r.vrElement.visible = showRings;
    }
    for (final c in engine.constellations) {
      c.vrElement.visible = showConstellations;
    }

    _stereoPainter = VRStereoPainter(
      renderer: engine.scene,
      camera: engine.camera,
      projection: engine.projection,
      showLensVignette: true,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _stereoPainter.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant VrStereo360Painter oldDelegate) => true;
}
