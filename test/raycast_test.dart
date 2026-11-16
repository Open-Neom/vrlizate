import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

Ray _ray(Vector3 origin, Vector3 direction) =>
    Ray.originDirection(origin, direction);

void main() {
  group('Raycaster', () {
    late Raycaster raycaster;

    setUp(() {
      raycaster = Raycaster();
    });

    test('ray hits child node in front', () {
      final root = Node(name: 'root');
      final target = Node(name: 'target');
      target.transform.position = Vector3(0, 0, -5);
      target.onTransformChanged();
      root.addChild(target);

      final ray = _ray(Vector3(0, 0, 0), Vector3(0, 0, -1));
      final hits = raycaster.cast(ray, root);

      // Both root (at origin) and target (at -5) should be hit
      expect(hits.any((h) => h.node.name == 'target'), isTrue);
    });

    test('ray misses node far to the side', () {
      final root = Node(name: 'root');
      final target = Node(name: 'target');
      target.transform.position = Vector3(100, 0, -5);
      target.onTransformChanged();
      root.addChild(target);

      final ray = _ray(Vector3(0, 0, 0), Vector3(0, 0, -1));
      final hits = raycaster.cast(ray, root);

      expect(hits.where((h) => h.node.name == 'target'), isEmpty);
    });

    test('ray behind node does not hit target', () {
      final root = Node(name: 'root');
      final target = Node(name: 'target');
      target.transform.position = Vector3(0, 0, 5);
      target.onTransformChanged();
      root.addChild(target);

      final ray = _ray(Vector3(0, 0, 0), Vector3(0, 0, -1));
      final hits = raycaster.cast(ray, root);

      // Root might be hit, but target at z=5 is behind the ray
      expect(hits.where((h) => h.node.name == 'target'), isEmpty);
    });

    test('nearest hit from two targets returns closer one', () {
      final root = Node(name: 'root');

      final near = Node(name: 'near');
      near.transform.position = Vector3(0, 0, -3);
      near.onTransformChanged();
      root.addChild(near);

      final far = Node(name: 'far');
      far.transform.position = Vector3(0, 0, -10);
      far.onTransformChanged();
      root.addChild(far);

      final ray = _ray(Vector3(0, 0, 0), Vector3(0, 0, -1));
      final hits = raycaster
          .cast(ray, root)
          .where((h) => h.node.name != 'root')
          .toList();

      expect(hits, isNotEmpty);
      expect(hits.first.node.name, equals('near'));
    });

    test('invisible nodes are skipped', () {
      final root = Node(name: 'root');
      final hidden = Node(name: 'hidden')..visible = false;
      hidden.transform.position = Vector3(0, 0, -3);
      hidden.onTransformChanged();
      root.addChild(hidden);

      final ray = _ray(Vector3(0, 0, 0), Vector3(0, 0, -1));
      final hits = raycaster.cast(ray, root);

      expect(hits.where((h) => h.node.name == 'hidden'), isEmpty);
    });

    test('maxDistance limits hit range', () {
      final root = Node(name: 'root');
      final far = Node(name: 'far');
      far.transform.position = Vector3(0, 0, -50);
      far.onTransformChanged();
      root.addChild(far);

      final ray = _ray(Vector3(0, 0, 0), Vector3(0, 0, -1));
      final hits = raycaster.cast(ray, root, maxDistance: 10);

      expect(hits.where((h) => h.node.name == 'far'), isEmpty);
    });

    test('hits are sorted by distance (nearest first)', () {
      final root = Node(name: 'root');

      final a = Node(name: 'a');
      a.transform.position = Vector3(0, 0, -8);
      a.onTransformChanged();
      root.addChild(a);

      final b = Node(name: 'b');
      b.transform.position = Vector3(0, 0, -3);
      b.onTransformChanged();
      root.addChild(b);

      final ray = _ray(Vector3(0, 0, 0), Vector3(0, 0, -1));
      final hits = raycaster.cast(ray, root);

      for (var i = 1; i < hits.length; i++) {
        expect(hits[i].distance, greaterThanOrEqualTo(hits[i - 1].distance));
      }
    });

    void expectNearestMatches(
      Ray ray,
      Node root, {
      double maxDistance = 1000,
      bool Function(Node node)? where,
    }) {
      final hits = raycaster
          .cast(ray, root, maxDistance: maxDistance)
          .where((hit) => where == null || where(hit.node))
          .toList();
      final actual = raycaster.castNearest(
        ray,
        root,
        maxDistance: maxDistance,
        where: where,
      );
      if (hits.isEmpty) {
        expect(actual, isNull);
      } else {
        expect(actual, isNotNull);
        expect(actual!.node, same(hits.first.node));
        expect(actual.distance, hits.first.distance);
        expect(actual.point, hits.first.point);
        expect(actual.normal, hits.first.normal);
      }
    }

    test('nearest filters only self hits and observes live pointables', () {
      final root = Node(name: 'root');
      final group = Node(name: 'group');
      final near = Node(name: 'near');
      near.transform.position.z = -3;
      near.onTransformChanged();
      final far = Node(name: 'far');
      far.pointable = Pointable(node: far);
      far.transform.position.z = -8;
      far.onTransformChanged();
      group.addChild(near);
      root
        ..addChild(group)
        ..addChild(far);
      final ray = _ray(Vector3(0, 0, 2), Vector3(0, 0, -1));
      bool selectable(Node node) => node.pointable != null;

      expectNearestMatches(ray, root, where: selectable);
      expect(raycaster.castNearest(ray, root, where: selectable)!.node, far);
      near.pointable = Pointable(node: near);
      expectNearestMatches(ray, root, where: selectable);
      expect(raycaster.castNearest(ray, root, where: selectable)!.node, near);
      group.visible = false;
      expectNearestMatches(ray, root, where: selectable);
      expect(raycaster.castNearest(ray, root, where: selectable)!.node, far);
      group.visible = true;
      near.pointable = null;
      expectNearestMatches(ray, root, where: selectable);
      far.pointable = null;
      expectNearestMatches(ray, root, where: selectable);
    });

    test('nearest follows transform and hierarchy changes', () {
      final root = Node(name: 'root');
      final group = Node(name: 'group');
      group.transform.rotation = Quaternion.axisAngle(Vector3(0, 0, 1), .4);
      group.transform.scale = Vector3(2, .5, 1.5);
      group.onTransformChanged();
      final target = Node(name: 'target');
      target.transform.position.z = -4;
      target.onTransformChanged();
      group.addChild(target);
      root.addChild(group);
      final ray = _ray(Vector3(0, 0, 2), Vector3(0, 0, -2));
      bool targetOnly(Node node) => node.name == 'target';

      expectNearestMatches(ray, root);
      expectNearestMatches(ray, root, where: targetOnly);
      expect(raycaster.castNearest(ray, root, where: targetOnly), isNotNull);
      target.transform.position = Vector3(20, 0, -4);
      target.onTransformChanged();
      expectNearestMatches(ray, root, where: targetOnly);
      expect(raycaster.castNearest(ray, root, where: targetOnly), isNull);
      group.removeChild(target);
      expectNearestMatches(ray, root, where: targetOnly);
      target.transform.position = Vector3(0, 0, -2);
      target.onTransformChanged();
      root.addChild(target);
      expectNearestMatches(ray, root, where: targetOnly);
      expect(raycaster.castNearest(ray, root, where: targetOnly), isNotNull);
    });

    test(
      'nearest keeps children inside a large enclosing parent searchable',
      () {
        final root = Node(name: 'root');
        final earlier = Node(name: 'target_far');
        earlier.transform.position.z = -5;
        earlier.onTransformChanged();
        final group = Node(name: 'enclosing');
        final nearer = Node(name: 'target_near');
        nearer.transform.position.z = -2;
        nearer.onTransformChanged();
        final extent = Node(name: 'extent');
        extent.transform.position.z = -80;
        extent.onTransformChanged();
        group
          ..addChild(nearer)
          ..addChild(extent);
        root
          ..addChild(earlier)
          ..addChild(group);
        final ray = _ray(Vector3.zero(), Vector3(0, 0, -1));
        bool targets(Node node) => node.name.startsWith('target_');

        expect(group.worldAabb.containsPoint(ray.origin), isTrue);
        expectNearestMatches(ray, root, where: targets);
        expect(raycaster.castNearest(ray, root, where: targets)!.node, nearer);
      },
    );

    test('nearest preserves range and parallel-axis intersection behavior', () {
      final root = Node(name: 'root');
      final target = Node(name: 'target');
      target.transform.position.z = -5;
      target.onTransformChanged();
      root.addChild(target);
      bool targetOnly(Node node) => identical(node, target);

      for (final origin in [Vector3(0, 0, 2), Vector3(3, 0, 2)]) {
        for (final direction in [
          Vector3(0, 0, -1),
          Vector3(0, 1, 0),
          Vector3(0, 0, 1),
        ]) {
          for (final range in [3.0, 7.0, 1000.0]) {
            expectNearestMatches(
              _ray(origin, direction),
              root,
              maxDistance: range,
              where: targetOnly,
            );
          }
        }
      }
    });

    test(
      'engine gaze and tap select pointables beyond decorative geometry',
      () async {
        final engine = VREngine();
        addTearDown(engine.dispose);
        engine.enableGazePointer();
        engine.gazePointer!.enableHaptics = false;
        engine.externalDwellSuppressed = true;
        final geometry = CubeGeometry();
        final decorative = MeshNode(name: 'decoration', geometry: geometry);
        decorative.transform.position.z = -2;
        decorative.onTransformChanged();
        final target = MeshNode(name: 'target', geometry: geometry);
        target.transform.position.z = -5;
        target.onTransformChanged();
        final pressed = <Node>[];
        target.pointable = Pointable(
          node: target,
          onPress: (node, _) => pressed.add(node),
        );
        engine.scene
          ..add(decorative)
          ..add(target);
        engine.setExternalInteractionRay(
          _ray(Vector3(0, 0, 2), Vector3(0, 0, -1)),
        );

        engine.step(1 / 60, integrateInput: false);
        expect(engine.gazePointer!.gazeTargetId, 'target');
        expect(target.pointable!.isHovered, isTrue);
        engine.handleTap();
        expect(pressed, [target]);

        decorative.pointable = Pointable(
          node: decorative,
          onPress: (node, _) => pressed.add(node),
        );
        engine.step(1 / 60, integrateInput: false);
        expect(engine.gazePointer!.gazeTargetId, 'decoration');
        expect(target.pointable!.isHovered, isFalse);
        engine.handleTap();
        expect(pressed, [target, decorative]);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      },
    );
  });
}
