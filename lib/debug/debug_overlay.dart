import 'dart:ui';

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import '../core/engine/vr_engine.dart';

/// Debug overlay that displays performance metrics in VR.
class DebugOverlay {
  bool enabled;
  bool showFps;
  bool showNodeCount;
  bool showCullingStats;
  bool showCameraInfo;

  DebugOverlay({
    this.enabled = false,
    this.showFps = true,
    this.showNodeCount = true,
    this.showCullingStats = true,
    this.showCameraInfo = false,
  });

  void render(Canvas canvas, Size size, VREngine engine) {
    if (!enabled) return;

    final lines = <String>[];

    if (showFps) {
      lines.add('FPS: ${engine.fps.toStringAsFixed(1)}');
      lines.add('Frame: ${engine.frameTimeMs.toStringAsFixed(1)}ms');
    }

    if (showNodeCount) {
      lines.add('Rendered: ${engine.renderedCount}');
    }

    if (showCullingStats) {
      lines.add('Culled: ${engine.culledCount}');
    }

    if (showCameraInfo) {
      final pos = engine.cameraRig.position;
      lines.add(
        'Pos: ${pos.x.toStringAsFixed(1)}, ${pos.y.toStringAsFixed(1)}, ${pos.z.toStringAsFixed(1)}',
      );
    }

    // Render in top-left corner
    const textStyle = TextStyle(
      color: Color(0xCC00FF00),
      fontSize: 10,
      fontFamily: 'monospace',
    );

    double y = 8;
    for (final line in lines) {
      final painter = TextPainter(
        text: TextSpan(text: line, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      // Background
      canvas.drawRect(
        Rect.fromLTWH(4, y - 1, painter.width + 8, painter.height + 2),
        Paint()..color = const Color(0x80000000),
      );

      painter.paint(canvas, Offset(8, y));
      y += painter.height + 4;
    }
  }
}
