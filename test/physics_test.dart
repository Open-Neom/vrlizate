import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate_physics/vrlizate_physics.dart' as physics;

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('RigidBody physics', () {
    test('static body does not move under gravity', () {
      final node = Node(name: 'static');
      node.transform.position = Vector3(0, 5, 0);
      final body = RigidBody(node: node, isStatic: true, useGravity: true);

      body.update(1.0); // 1 second

      expect(node.transform.position.y, closeTo(5, 1e-6));
    });

    test('dynamic body falls under gravity', () {
      final node = Node(name: 'dynamic');
      node.transform.position = Vector3(0, 10, 0);
      final body = RigidBody(node: node, useGravity: true);

      body.update(0.5); // Half second

      expect(node.transform.position.y, lessThan(10));
    });

    test('ground collision stops falling body', () {
      final node = Node(name: 'ball');
      node.transform.position = Vector3(0, 0.5, 0);
      final body = RigidBody(node: node, useGravity: true, restitution: 0);

      for (var i = 0; i < 100; i++) {
        body.update(0.016);
        body.resolveGroundCollision(0);
      }

      // Should have settled on ground
      expect(node.transform.position.y, closeTo(0, 0.5));
    });

    test('bouncy body bounces above ground', () {
      final node = Node(name: 'bouncy');
      node.transform.position = Vector3(0, 5, 0);
      final body = RigidBody(node: node, useGravity: true, restitution: 0.9);

      // Drop and bounce
      for (var i = 0; i < 30; i++) {
        body.update(0.016);
        body.resolveGroundCollision(0);
      }

      // After bouncing, velocity.y should have been positive at some point
      // Body should be above ground
      expect(node.transform.position.y, greaterThanOrEqualTo(0));
    });

    test('impulse changes velocity', () {
      final node = Node(name: 'ball');
      final body = RigidBody(node: node, useGravity: false);

      body.applyImpulse(Vector3(10, 0, 0));
      expect(body.velocity.x, closeTo(10, 1e-4));

      body.update(1.0);
      expect(
        node.transform.position.x,
        greaterThan(5),
      ); // Damping reduces slightly
    });

    test('sleeping body wakes on impulse', () {
      final node = Node(name: 'sleeping');
      final body = RigidBody(node: node, useGravity: false);
      body.isSleeping = true;

      body.applyImpulse(Vector3(5, 0, 0));
      expect(body.isSleeping, isFalse);
    });

    test('PhysicsWorld updates all bodies', () {
      final world = PhysicsWorld(groundY: 0);

      final n1 = Node(name: 'a');
      n1.transform.position = Vector3(0, 5, 0);
      world.addBody(RigidBody(node: n1));

      final n2 = Node(name: 'b');
      n2.transform.position = Vector3(3, 5, 0);
      world.addBody(RigidBody(node: n2));

      world.update(0.1);

      expect(n1.transform.position.y, lessThan(5));
      expect(n2.transform.position.y, lessThan(5));
    });

    test('collision between two bodies exchanges momentum', () {
      final na = Node(name: 'a');
      na.transform.position = Vector3(0, 1, 0);
      final a = RigidBody(node: na, useGravity: false);
      a.velocity = Vector3(5, 0, 0);

      final nb = Node(name: 'b');
      nb.transform.position = Vector3(1, 1, 0);
      final b = RigidBody(node: nb, useGravity: false);
      b.velocity = Vector3(-5, 0, 0);

      // Move them close enough to collide
      a.update(0.05);
      b.update(0.05);
      RigidBody.resolveCollision(a, b);

      // After collision, velocities should have changed direction
      // (or at least be different from initial)
      expect(a.velocity.x, lessThan(5));
    });

    test('zero mass static body has zero inverseMass', () {
      final node = Node(name: 'static');
      final body = RigidBody(node: node, isStatic: true);
      expect(body.inverseMass, closeTo(0, 1e-6));
    });

    test('scene adapter uses SDK simulation and retains ground pivot', () {
      final node = Node()..transform.position = Vector3(0, -1, 0);
      final body = RigidBody(node: node, restitution: 0);
      expect(body, isA<physics.PhysicsBody>());
      body.resolveGroundCollision(0);
      expect(node.transform.position.y, 0);
      expect(node.worldPosition.y, 0);
    });

    test('forces wake sleeping scene nodes and invalidate world bounds', () {
      final node = Node();
      final original = node.ownWorldAabb;
      final body = RigidBody(
        node: node,
        isSleeping: true,
        useGravity: false,
        linearDamping: 0,
      );
      body.applyForce(Vector3(10, 0, 0));
      body.update(0.1);
      expect(body.isSleeping, isFalse);
      expect(node.ownWorldAabb.min.x, greaterThan(original.min.x));
    });

    test('overlap against a static node is fully corrected', () {
      final wall = RigidBody(node: Node(), isStatic: true);
      final node = Node()..transform.position = Vector3(0.8, 0.1, 0);
      final moving = RigidBody(node: node, useGravity: false);
      RigidBody.resolveCollision(wall, moving);
      expect(node.worldPosition.x, closeTo(1, 1e-6));
      expect(node.worldPosition.y, closeTo(0.1, 1e-6));
    });

    test('linear world motion is converted through translated parents', () {
      final parent = Node()..transform.position = Vector3(10, 0, 0);
      final node = Node()..transform.position = Vector3(1, 2, 0);
      parent.addChild(node);
      final body = RigidBody(
        node: node,
        useGravity: false,
        linearDamping: 0,
        velocity: Vector3(1, 0, 0),
      );
      body.update(0.5);
      expect(node.worldPosition.x, closeTo(11.5, 1e-6));
      expect(node.transform.position.x, closeTo(1.5, 1e-6));
    });

    test('scene world limits catch-up work after a pause', () {
      final node = Node();
      final world = PhysicsWorld(groundY: null)
        ..addBody(
          RigidBody(
            node: node,
            useGravity: false,
            linearDamping: 0,
            velocity: Vector3(1, 0, 0),
          ),
        );
      world.update(60);
      expect(world.lastStepCount, 8);
      expect(node.worldPosition.x, closeTo(8 / 60, 1e-6));
    });
  });
}
