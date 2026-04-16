import 'dart:ui';

import 'package:vector_math/vector_math.dart';

import '../scene/node.dart';

/// A grid rendered on the XZ plane for spatial reference.
class GridFloor extends Node {
  final double size;
  final int divisions;
  final Color color;
  final Color centerLineColor;

  GridFloor({
    this.size = 20,
    this.divisions = 20,
    this.color = const Color(0x30FFFFFF),
    this.centerLineColor = const Color(0x60FFFFFF),
  }) : super(name: 'grid_floor');

  @override
  void onRender(Canvas canvas, Matrix4 viewProjection) {
    final half = size / 2;
    final step = size / divisions;
    final mvp = viewProjection * worldMatrix;

    for (var i = 0; i <= divisions; i++) {
      final pos = -half + i * step;
      final isCenter = i == divisions ~/ 2;
      final lineColor = isCenter ? centerLineColor : color;

      // Lines along X axis
      _drawLine3D(
        canvas,
        mvp,
        Vector3(pos, 0, -half),
        Vector3(pos, 0, half),
        lineColor,
      );

      // Lines along Z axis
      _drawLine3D(
        canvas,
        mvp,
        Vector3(-half, 0, pos),
        Vector3(half, 0, pos),
        lineColor,
      );
    }
  }

  void _drawLine3D(
    Canvas canvas,
    Matrix4 mvp,
    Vector3 a,
    Vector3 b,
    Color color,
  ) {
    final pa = _project(mvp, a);
    final pb = _project(mvp, b);
    if (pa == null || pb == null) return;

    canvas.drawLine(
      pa,
      pb,
      Paint()
        ..color = color
        ..strokeWidth = 0.5,
    );
  }

  Offset? _project(Matrix4 mvp, Vector3 v) {
    final clip = mvp.transformed(Vector4(v.x, v.y, v.z, 1));
    if (clip.w <= 0.001) return null;
    return Offset(clip.x / clip.w, clip.y / clip.w);
  }
}
