import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('Node hierarchy', () {
    test('addChild sets parent correctly', () {
      final parent = Node(name: 'parent');
      final child = Node(name: 'child');
      parent.addChild(child);

      expect(child.parent, equals(parent));
      expect(parent.childCount, equals(1));
    });

    test('removeChild clears parent', () {
      final parent = Node(name: 'parent');
      final child = Node(name: 'child');
      parent.addChild(child);
      parent.removeChild(child);

      expect(child.parent, isNull);
      expect(parent.childCount, equals(0));
    });

    test('addChild to new parent removes from old parent', () {
      final old = Node(name: 'old');
      final newP = Node(name: 'new');
      final child = Node(name: 'child');

      old.addChild(child);
      newP.addChild(child);

      expect(old.childCount, equals(0));
      expect(newP.childCount, equals(1));
      expect(child.parent, equals(newP));
    });

    test('removeFromParent works when no parent', () {
      final orphan = Node(name: 'orphan');
      // Should not throw
      orphan.removeFromParent();
    });

    test('worldMatrix accumulates parent transforms', () {
      final parent = Node(name: 'parent');
      parent.transform.position = Vector3(10, 0, 0);

      final child = Node(name: 'child');
      child.transform.position = Vector3(0, 5, 0);
      parent.addChild(child);

      final worldPos = child.worldPosition;
      expect(worldPos.x, closeTo(10, 1e-4));
      expect(worldPos.y, closeTo(5, 1e-4));
    });

    test('worldMatrix propagates through 3 levels', () {
      final root = Node(name: 'root');
      root.transform.position = Vector3(1, 0, 0);

      final mid = Node(name: 'mid');
      mid.transform.position = Vector3(0, 1, 0);
      root.addChild(mid);

      final leaf = Node(name: 'leaf');
      leaf.transform.position = Vector3(0, 0, 1);
      mid.addChild(leaf);

      final wp = leaf.worldPosition;
      expect(wp.x, closeTo(1, 1e-4));
      expect(wp.y, closeTo(1, 1e-4));
      expect(wp.z, closeTo(1, 1e-4));
    });

    test('dirty flag propagates to children on parent transform change', () {
      final parent = Node(name: 'parent');
      final child = Node(name: 'child');
      parent.addChild(child);

      // Access worldMatrix to cache it
      child.worldMatrix;

      // Change parent — child should be dirty
      parent.transform.position = Vector3(99, 0, 0);
      parent.onTransformChanged();

      final wp = child.worldPosition;
      expect(wp.x, closeTo(99, 1e-4));
    });

    test('findChild searches recursively', () {
      final root = Node(name: 'root');
      final a = Node(name: 'a');
      final b = Node(name: 'b');
      final deep = Node(name: 'deep_target');
      root.addChild(a);
      a.addChild(b);
      b.addChild(deep);

      expect(root.findChild('deep_target'), equals(deep));
      expect(root.findChild('nonexistent'), isNull);
    });

    test('traverse visits all nodes', () {
      final root = Node(name: 'root');
      root.addChild(Node(name: 'a'));
      root.addChild(Node(name: 'b'));
      root.children[0].addChild(Node(name: 'c'));

      final visited = <String>[];
      root.traverse((n) => visited.add(n.name));

      expect(visited, equals(['root', 'a', 'c', 'b']));
    });

    test('collectVisible skips invisible nodes', () {
      final root = Node(name: 'root');
      final visible = Node(name: 'visible');
      final hidden = Node(name: 'hidden')..visible = false;
      root.addChild(visible);
      root.addChild(hidden);

      final result = root.collectVisible();
      expect(result.any((n) => n.name == 'visible'), isTrue);
      expect(result.any((n) => n.name == 'hidden'), isFalse);
    });
  });
}
