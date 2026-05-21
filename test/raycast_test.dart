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
  });
}
