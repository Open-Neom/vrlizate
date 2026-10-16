import 'package:vector_math/vector_math.dart';
import 'package:vrlizate_physics/vrlizate_physics.dart' as physics;

import '../scene/node.dart';

/// Scene-graph adapter for the SDK's render-independent physics module.
/// Existing experiences retain `RigidBody(node: ...)` and pivot-ground behavior.
class RigidBody extends physics.PhysicsBody {
  final Node node;

  static final Vector3 gravity = physics.PhysicsBody.gravity;

  RigidBody({
    required this.node,
    super.velocity,
    super.angularVelocity,
    super.mass,
    super.restitution,
    super.friction,
    super.linearDamping,
    super.angularDamping,
    super.isStatic,
    super.useGravity,
    super.isSleeping,
  }) : super(
         transform: _NodePhysicsTransform(node),
         groundAtPivot: true,
         boundsProvider: () {
           final bounds = node.ownWorldAabb;
           return physics.PhysicsBounds(bounds.min, bounds.max);
         },
       );

  static void resolveCollision(RigidBody a, RigidBody b) =>
      physics.PhysicsBody.resolveCollision(a, b);
}

/// Compatibility facade using the same SDK simulation as standalone bodies.
class PhysicsWorld extends physics.PhysicsWorld<RigidBody> {
  PhysicsWorld({
    super.groundY = 0,
    super.gravity,
    super.fixedTimeStep,
    super.maxSubSteps,
    super.maxFrameTime,
    super.maxBodies,
  });
}

class _NodePhysicsTransform implements physics.PhysicsTransform {
  final Node node;

  _NodePhysicsTransform(this.node) {
    node.onTransformChanged();
  }

  @override
  Vector3 get position => node.worldPosition;

  @override
  set position(Vector3 value) {
    final parent = node.parent;
    if (parent == null) {
      node.transform.position = value;
    } else {
      final inverse = parent.worldMatrix.clone();
      if (inverse.invert() == 0) {
        throw StateError(
          'A physics node cannot have a singular parent transform.',
        );
      }
      node.transform.position = inverse.transformed3(value);
    }
  }

  @override
  void rotate(Quaternion delta) {
    // Angular velocity follows the existing local rotation convention.
    node.transform.rotate(delta);
  }

  @override
  void onChanged() => node.onTransformChanged();
}
