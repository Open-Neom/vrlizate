import 'package:vector_math/vector_math.dart';

import '../core/math/aabb.dart';
import '../scene/node.dart';

/// Simple 3D rigid body physics for VR interactions.
/// Handles gravity, velocity, collision response, and damping.
class RigidBody {
  final Node node;

  Vector3 velocity;
  Vector3 angularVelocity;
  double mass;
  double restitution;
  double friction;
  double linearDamping;
  double angularDamping;
  bool isStatic;
  bool useGravity;
  bool isSleeping;

  /// Accumulated forces applied this frame.
  Vector3 _forceAccumulator = Vector3.zero();

  static final Vector3 gravity = Vector3(0, -9.81, 0);

  RigidBody({
    required this.node,
    Vector3? velocity,
    Vector3? angularVelocity,
    this.mass = 1.0,
    this.restitution = 0.3,
    this.friction = 0.5,
    this.linearDamping = 0.01,
    this.angularDamping = 0.05,
    this.isStatic = false,
    this.useGravity = true,
    this.isSleeping = false,
  }) : velocity = velocity ?? Vector3.zero(),
       angularVelocity = angularVelocity ?? Vector3.zero();

  double get inverseMass => isStatic ? 0 : 1 / mass;

  void applyForce(Vector3 force) {
    if (isStatic) return;
    _forceAccumulator += force;
  }

  void applyImpulse(Vector3 impulse) {
    if (isStatic) return;
    velocity += impulse * inverseMass;
    isSleeping = false;
  }

  void update(double dt) {
    if (isStatic || isSleeping) return;

    // Apply gravity
    if (useGravity) {
      _forceAccumulator += gravity * mass;
    }

    // Integrate forces → velocity
    velocity += _forceAccumulator * inverseMass * dt;
    _forceAccumulator = Vector3.zero();

    // Damping
    velocity *= (1 - linearDamping);
    angularVelocity *= (1 - angularDamping);

    // Integrate velocity → position
    node.transform.position = node.transform.position + velocity * dt;

    // Integrate angular velocity → rotation
    if (angularVelocity.length > 0.001) {
      final angle = angularVelocity.length * dt;
      final axis = angularVelocity.normalized();
      node.transform.rotate(Quaternion.axisAngle(axis, angle));
    }

    node.onTransformChanged();

    // Sleep check
    if (velocity.length < 0.01 && angularVelocity.length < 0.01) {
      isSleeping = true;
    }
  }

  /// Simple ground plane collision at y=groundY.
  void resolveGroundCollision(double groundY) {
    if (isStatic) return;
    final pos = node.transform.position;

    if (pos.y < groundY) {
      node.transform.position = Vector3(pos.x, groundY, pos.z);
      velocity = Vector3(
        velocity.x * friction,
        -velocity.y * restitution,
        velocity.z * friction,
      );
      node.onTransformChanged();

      if (velocity.y.abs() < 0.1) {
        velocity = Vector3(velocity.x, 0, velocity.z);
      }
    }
  }

  /// AABB-based collision between two rigid bodies.
  static void resolveCollision(RigidBody a, RigidBody b) {
    if (a.isStatic && b.isStatic) return;

    final aabbA = a.node.worldAabb;
    final aabbB = b.node.worldAabb;

    if (!aabbA.intersectsAabb(aabbB)) return;

    // Collision normal (from A to B center)
    final normal = (b.node.worldPosition - a.node.worldPosition)..normalize();

    // Relative velocity
    final relVel = b.velocity - a.velocity;
    final velAlongNormal = relVel.dot(normal);

    // Don't resolve if separating
    if (velAlongNormal > 0) return;

    // Restitution
    final e = (a.restitution + b.restitution) / 2;

    // Impulse scalar
    final j = -(1 + e) * velAlongNormal / (a.inverseMass + b.inverseMass);

    // Apply impulse
    a.applyImpulse(normal * (-j));
    b.applyImpulse(normal * j);

    // Position correction (prevent sinking)
    final overlap = _overlapAmount(aabbA, aabbB);
    if (overlap > 0) {
      final correction = normal * (overlap * 0.5);
      if (!a.isStatic) {
        a.node.transform.position = a.node.transform.position - correction;
      }
      if (!b.isStatic) {
        b.node.transform.position = b.node.transform.position + correction;
      }
      a.node.onTransformChanged();
      b.node.onTransformChanged();
    }
  }

  static double _overlapAmount(Aabb a, Aabb b) {
    final overlapX = (a.max.x - b.min.x).clamp(0, double.infinity);
    final overlapY = (a.max.y - b.min.y).clamp(0, double.infinity);
    final overlapZ = (a.max.z - b.min.z).clamp(0, double.infinity);
    return [
      overlapX,
      overlapY,
      overlapZ,
    ].reduce((a, b) => a < b ? a : b).toDouble();
  }
}

/// Simple physics world that manages rigid bodies.
class PhysicsWorld {
  final List<RigidBody> bodies = [];
  double groundY;

  PhysicsWorld({this.groundY = 0});

  void addBody(RigidBody body) => bodies.add(body);
  void removeBody(RigidBody body) => bodies.remove(body);

  void update(double dt) {
    // Update bodies
    for (final body in bodies) {
      body.update(dt);
      body.resolveGroundCollision(groundY);
    }

    // Check collisions (O(n²) — fine for small VR scenes)
    for (var i = 0; i < bodies.length; i++) {
      for (var j = i + 1; j < bodies.length; j++) {
        RigidBody.resolveCollision(bodies[i], bodies[j]);
      }
    }
  }
}
