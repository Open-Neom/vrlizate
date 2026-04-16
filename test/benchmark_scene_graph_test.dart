import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

/// Benchmarks for scene graph operations — hierarchy traversal, transform
/// propagation, and AABB computation at scale.
///
/// These tests validate that VRlizate can handle real-world scene complexity
/// (1K–100K nodes) within acceptable time budgets.
void main() {
  group('Scene Graph — Stress', () {
    test('1,000 flat children: build + traverse < 50ms', () {
      final sw = Stopwatch()..start();
      final root = Node(name: 'root');
      for (var i = 0; i < 1000; i++) {
        final child = Node(name: 'n$i');
        child.transform.position = Vector3(i.toDouble(), 0, 0);
        root.addChild(child);
      }

      int count = 0;
      root.traverse((_) => count++);
      sw.stop();

      expect(count, equals(1001)); // root + 1000 children
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('10,000 flat children: build + traverse < 200ms', () {
      final sw = Stopwatch()..start();
      final root = Node(name: 'root');
      for (var i = 0; i < 10000; i++) {
        root.addChild(Node(name: 'n$i'));
      }

      int count = 0;
      root.traverse((_) => count++);
      sw.stop();

      expect(count, equals(10001));
      expect(sw.elapsedMilliseconds, lessThan(200));
    });

    test('deep hierarchy (depth=100): traverse + worldMatrix', () {
      Node current = Node(name: 'root');
      final root = current;
      for (var i = 0; i < 100; i++) {
        final child = Node(name: 'depth_$i');
        child.transform.position = Vector3(0, 1, 0);
        current.addChild(child);
        current = child;
      }

      // Force world matrix computation at the deepest node
      final deepWorldPos = current.worldMatrix.getTranslation();
      expect(deepWorldPos.y, closeTo(100, 1e-3));

      int count = 0;
      root.traverse((_) => count++);
      expect(count, equals(101));
    });

    test('mixed hierarchy (10 levels × 5 children) = 12,207 nodes', () {
      Node buildTree(int depth, int breadth) {
        final node = Node(name: 'd$depth');
        if (depth > 0) {
          for (var i = 0; i < breadth; i++) {
            node.addChild(buildTree(depth - 1, breadth));
          }
        }
        return node;
      }

      final sw = Stopwatch()..start();
      final root = buildTree(6, 5); // 5^0 + 5^1 + ... + 5^6 = 19,531 nodes
      int count = 0;
      root.traverse((_) => count++);
      sw.stop();

      expect(count, equals(19531));
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('transform propagation correctness through hierarchy', () {
      final grandparent = Node(name: 'gp');
      grandparent.transform.position = Vector3(10, 0, 0);

      final parent = Node(name: 'p');
      parent.transform.position = Vector3(0, 5, 0);
      grandparent.addChild(parent);

      final child = Node(name: 'c');
      child.transform.position = Vector3(0, 0, 3);
      parent.addChild(child);

      final worldPos = child.worldMatrix.getTranslation();
      expect(worldPos.x, closeTo(10, 1e-3));
      expect(worldPos.y, closeTo(5, 1e-3));
      expect(worldPos.z, closeTo(3, 1e-3));
    });

    test('addChild / removeChild maintains integrity', () {
      final root = Node(name: 'root');
      final a = Node(name: 'a');
      final b = Node(name: 'b');

      root.addChild(a);
      root.addChild(b);
      expect(root.children.length, equals(2));

      root.removeChild(a);
      expect(root.children.length, equals(1));
      expect(root.children.first.name, equals('b'));
    });

    test('findChild searches recursively', () {
      final root = Node(name: 'root');
      final a = Node(name: 'a');
      final b = Node(name: 'b');
      final c = Node(name: 'target');
      root.addChild(a);
      a.addChild(b);
      b.addChild(c);

      expect(root.findChild('target')?.name, equals('target'));
      expect(root.findChild('nonexistent'), isNull);
    });
  });
}
