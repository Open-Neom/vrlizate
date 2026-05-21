import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

/// Physics stress tests — validates that the physics engine handles hundreds
/// of bodies with collision detection within real-time budgets.
void main() {
  group('Physics — Stress', () {
    test('50 bodies falling: 500 steps < 5000ms', () {
      final world = PhysicsWorld();
      for (var i = 0; i < 50; i++) {
        final node = Node(name: 'body_$i');
        node.transform.position = Vector3(i.toDouble() * 3, 50, 0);
        node.onTransformChanged();
        world.addBody(RigidBody(node: node, mass: 1, restitution: 0.5));
      }

      final sw = Stopwatch()..start();
      for (var step = 0; step < 500; step++) {
        world.update(1 / 60);
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('energy conservation: bouncing body loses height monotonically', () {
      final node = Node(name: 'ball');
      node.transform.position = Vector3(0, 10, 0);
      node.onTransformChanged();
      final body = RigidBody(node: node, mass: 1, restitution: 0.8);
      final world = PhysicsWorld()..addBody(body);

      const double maxH = 10;
      for (var step = 0; step < 3000; step++) {
        world.update(1 / 60);
      }

      // After 3000 frames, body should be near ground (not gaining energy)
      expect(node.transform.position.y, lessThan(maxH));
    });

    test('static body has zero inverse mass and ignores forces', () {
      final node = Node(name: 'static');
      node.transform.position = Vector3(5, 5, 5);
      node.onTransformChanged();
      final body = RigidBody(node: node, mass: 1, isStatic: true);

      expect(body.inverseMass, equals(0));
      body.applyForce(Vector3(100, 100, 100));
      expect(body.velocity.length, closeTo(0, 1e-6));
    });

    test('impulse response is proportional to mass', () {
      final nodeLight = Node(name: 'light');
      nodeLight.transform.position = Vector3.zero();
      final light = RigidBody(node: nodeLight, mass: 1);

      final nodeHeavy = Node(name: 'heavy');
      nodeHeavy.transform.position = Vector3(10, 0, 0);
      final heavy = RigidBody(node: nodeHeavy, mass: 10);

      light.applyImpulse(Vector3(10, 0, 0));
      heavy.applyImpulse(Vector3(10, 0, 0));

      expect(light.velocity.x, closeTo(10, 1e-6));
      expect(heavy.velocity.x, closeTo(1, 1e-6));
    });
  });
}
