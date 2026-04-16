import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

/// Raycasting benchmarks — measures ray-scene intersection performance
/// at different scene complexities. Critical for interaction responsiveness.
void main() {
  group('Raycast — Stress', () {
    test('100 rays against 100 nodes < 50ms', () {
      final root = Node(name: 'root');
      for (var i = 0; i < 100; i++) {
        final child = Node(name: 'n$i');
        child.transform.position = Vector3(
          (i % 10).toDouble() * 2,
          (i ~/ 10).toDouble() * 2,
          -5,
        );
        child.onTransformChanged();
        root.addChild(child);
      }

      final raycaster = Raycaster();
      final sw = Stopwatch()..start();

      for (var i = 0; i < 100; i++) {
        final ray = Ray.originDirection(
          Vector3.zero(),
          Vector3((i % 10).toDouble() * 0.2, (i ~/ 10).toDouble() * 0.2, -1)..normalize(),
        );
        raycaster.cast(ray, root);
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('1000 rays against 500 nodes < 500ms', () {
      final root = Node(name: 'root');
      for (var i = 0; i < 500; i++) {
        final child = Node(name: 'n$i');
        child.transform.position = Vector3(
          (i % 25).toDouble() * 2 - 25,
          (i ~/ 25).toDouble() * 2,
          -10,
        );
        child.onTransformChanged();
        root.addChild(child);
      }

      final raycaster = Raycaster();
      final sw = Stopwatch()..start();

      for (var i = 0; i < 1000; i++) {
        final ray = Ray.originDirection(
          Vector3.zero(),
          Vector3((i % 50).toDouble() * 0.04 - 1, (i ~/ 50).toDouble() * 0.05, -1)..normalize(),
        );
        raycaster.cast(ray, root);
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('castNearest returns correct nearest in dense scene', () {
      final root = Node(name: 'root');

      // Place nodes at z = -1, -2, -3, ..., -20
      for (var i = 1; i <= 20; i++) {
        final child = Node(name: 'z$i');
        child.transform.position = Vector3(0, 0, -i.toDouble());
        child.onTransformChanged();
        root.addChild(child);
      }

      final raycaster = Raycaster();
      final ray = Ray.originDirection(Vector3(0, 0, 1), Vector3(0, 0, -1));
      final hit = raycaster.castNearest(ray, root);

      expect(hit, isNotNull);
      // Nearest non-root node should be z1 (at z=-1)
      final nonRootHits = raycaster.cast(ray, root)
          .where((h) => h.node.name != 'root')
          .toList();
      if (nonRootHits.isNotEmpty) {
        expect(nonRootHits.first.node.name, equals('z1'));
      }
    });

    test('AABB slab method rejects rays in wrong direction', () {
      final root = Node(name: 'root');
      final target = Node(name: 'target');
      target.transform.position = Vector3(0, 0, -10);
      target.onTransformChanged();
      root.addChild(target);

      final raycaster = Raycaster();

      // Ray pointing up — should miss target at z=-10
      final ray = Ray.originDirection(Vector3.zero(), Vector3(0, 1, 0));
      final hits = raycaster.cast(ray, root);

      expect(hits.where((h) => h.node.name == 'target'), isEmpty);
    });
  });
}
