import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

MeshNode _box(String name, Vector3 position) {
  final box = MeshNode(name: name, geometry: CubeGeometry());
  box.transform.position = position;
  box.onTransformChanged();
  return box;
}

void main() {
  group('HybridRayTracer', () {
    test('finds the closest mesh along a bounded ray', () {
      final tracer = HybridRayTracer();
      final near = _box('near', Vector3(0, 0, -3));
      final far = _box('far', Vector3(0, 0, -8));

      final hit = tracer.traceClosest(
        origin: Vector3.zero(),
        direction: Vector3(0, 0, -1),
        nodes: [far, near],
        maxDistance: 20,
      );

      expect(hit, isNotNull);
      expect(hit!.node, same(near));
      expect(hit.distance, closeTo(2.5, 1e-6));
      expect(tracer.raysCast, 1);
      expect(tracer.hits, 1);
    });

    test('honors maximum distance and ignored receiver', () {
      final tracer = HybridRayTracer();
      final receiver = _box('receiver', Vector3(0, 0, -2));

      expect(
        tracer.traceClosest(
          origin: Vector3.zero(),
          direction: Vector3(0, 0, -1),
          nodes: [receiver],
          maxDistance: 1,
        ),
        isNull,
      );
      expect(
        tracer.traceClosest(
          origin: Vector3.zero(),
          direction: Vector3(0, 0, -1),
          nodes: [receiver],
          ignore: receiver,
          maxDistance: 10,
        ),
        isNull,
      );
    });

    test('darkens direct light when another mesh blocks it', () {
      final tracer = HybridRayTracer();
      final receiver = LitMeshNode(name: 'receiver', geometry: CubeGeometry());
      receiver.transform.position = Vector3.zero();
      receiver.onTransformChanged();
      final blocker = _box('blocker', Vector3(0, 2, 0));
      final light = Light.directional(direction: Vector3(0, -1, 0));

      final visibility = tracer.lightVisibility(
        receiver: receiver,
        light: light,
        nodes: [receiver, blocker],
        shadowVisibility: 0.25,
      );

      expect(visibility, 0.25);
    });
  });

  group('VrlizateScene', () {
    test('selects bounded mobile ray budgets by quality', () {
      final lite = VrlizateScene(quality: VrlizateSceneQuality.lite);
      final standard = VrlizateScene(quality: VrlizateSceneQuality.standard);
      final high = VrlizateScene(quality: VrlizateSceneQuality.high);

      expect(lite.maxRayQueriesPerFrame, 0);
      expect(standard.maxRayQueriesPerFrame, 18);
      expect(high.maxRayQueriesPerFrame, 36);
      expect(
        high.recommendedSphereSegments,
        greaterThan(standard.recommendedSphereSegments),
      );
      expect(high.backgroundColor, const Color(0xFF07111F));
    });
  });
}
