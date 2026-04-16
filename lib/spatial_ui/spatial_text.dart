import 'dart:ui';

import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, FontWeight, TextAlign;
import 'package:vector_math/vector_math.dart';

import 'billboard.dart';

/// 3D text that floats in VR space, always facing the camera.
class SpatialText extends Billboard {
  String text;
  double fontSize;
  Color color;
  FontWeight fontWeight;
  TextAlign textAlign;

  SpatialText({
    super.name = 'text',
    required super.cameraRig,
    required this.text,
    this.fontSize = 24,
    this.color = const Color(0xFFFFFFFF),
    this.fontWeight = FontWeight.w400,
    this.textAlign = TextAlign.center,
    super.lockY = true,
  });

  @override
  void onRender(Canvas canvas, Matrix4 viewProjection) {
    final mvp = viewProjection * worldMatrix;
    final center4 = mvp.transformed(Vector4(0, 0, 0, 1));
    if (center4.w <= 0.001) return;

    final ndcX = center4.x / center4.w;
    final ndcY = center4.y / center4.w;
    final depth = center4.w;
    final scaledFontSize = fontSize / depth;

    canvas.save();
    canvas.translate(ndcX, ndcY);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: scaledFontSize,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
    )..layout(maxWidth: 800 / depth);

    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );

    canvas.restore();
  }
}
