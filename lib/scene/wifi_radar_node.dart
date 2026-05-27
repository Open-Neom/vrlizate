import 'dart:math';
import 'dart:ui';
import 'package:vector_math/vector_math.dart';
import '../vrlizate.dart';

/// A 3D node representing the WiFi electromagnetic sensing grid and radar fields.
class WifiRadarNode extends Node {
  double pulseSpeed;
  Color radarColor;
  bool showGrid;
  
  static double time = 0.0;

  WifiRadarNode({
    super.name = 'wifi_radar',
    this.pulseSpeed = 4.0,
    this.radarColor = const Color(0x9910B981), // Semi-transparent Green
    this.showGrid = true,
  });

  @override
  void onRender(Canvas canvas, Matrix4 viewProjection) {
    if (!visible || !showGrid) return;

    // Draw electromagnetic waves as multiple concentric circles on the floor (Y = 0)
    final worldMatrix = transform.localMatrix;
    final origin = worldMatrix.getTranslation();

    final paint = Paint()
      ..color = radarColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Project points in circular arcs on the floor
    const numPulses = 3;
    const maxRadius = 4.0;
    
    for (var i = 0; i < numPulses; i++) {
      // Radius pulses outward over time
      final progress = ((time * pulseSpeed) / 10.0 + i / numPulses) % 1.0;
      final radius = progress * maxRadius;

      // Project circular points in 3D onto screen
      final points = <Offset>[];
      const numSegments = 16;
      
      for (var s = 0; s <= numSegments; s++) {
        final angle = (s / numSegments) * 2 * pi;
        final p3d = origin + Vector3(sin(angle) * radius, 0.0, cos(angle) * radius);
        
        final proj = _projectPoint(viewProjection, p3d);
        if (proj != null) {
          points.add(proj);
        }
      }

      if (points.length > 1) {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (var k = 1; k < points.length; k++) {
          path.lineTo(points[k].dx, points[k].dy);
        }
        
        // Fading intensity as it expands
        paint.color = radarColor.withValues(alpha: (1.0 - progress) * 0.3);
        canvas.drawPath(path, paint);
      }
    }
  }

  Offset? _projectPoint(Matrix4 mvp, Vector3 point) {
    final clip = mvp.transformed3(point);
    final w =
        mvp.storage[3] * point.x +
        mvp.storage[7] * point.y +
        mvp.storage[11] * point.z +
        mvp.storage[15];
    if (w <= 0.001) return null;

    final ndcX = clip.x / w;
    final ndcY = clip.y / w;
    
    // Convert NDC to screen-ish coordinates (width 800, height 600 viewport)
    final x = (ndcX + 1.0) * 400.0;
    final y = (1.0 - ndcY) * 300.0;
    return Offset(x, y);
  }
}
