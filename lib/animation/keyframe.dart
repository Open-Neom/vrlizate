import 'dart:math';

import 'package:vector_math/vector_math.dart';

/// A single keyframe in an animation track.
class Keyframe<T> {
  final double time;
  final T value;
  final EasingFunction easing;

  const Keyframe({
    required this.time,
    required this.value,
    this.easing = EasingFunction.linear,
  });
}

/// Easing functions for interpolation.
enum EasingFunction {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  elasticOut,
  bounceOut,
}

/// Applies easing to a normalized t (0-1).
double applyEasing(double t, EasingFunction easing) {
  return switch (easing) {
    EasingFunction.linear => t,
    EasingFunction.easeIn => t * t,
    EasingFunction.easeOut => 1 - (1 - t) * (1 - t),
    EasingFunction.easeInOut =>
      t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2,
    EasingFunction.elasticOut =>
      t == 0
          ? 0
          : t == 1
          ? 1
          : pow(2, -10 * t) * sin((t * 10 - 0.75) * (2 * pi / 3)) + 1,
    EasingFunction.bounceOut => _bounceOut(t),
  };
}

double _bounceOut(double t) {
  if (t < 1 / 2.75) return 7.5625 * t * t;
  if (t < 2 / 2.75) {
    t -= 1.5 / 2.75;
    return 7.5625 * t * t + 0.75;
  }
  if (t < 2.5 / 2.75) {
    t -= 2.25 / 2.75;
    return 7.5625 * t * t + 0.9375;
  }
  t -= 2.625 / 2.75;
  return 7.5625 * t * t + 0.984375;
}

/// Interpolates between two doubles.
double lerpDouble(double a, double b, double t) => a + (b - a) * t;

/// Interpolates between two Vector3.
Vector3 lerpVector3(Vector3 a, Vector3 b, double t) {
  return Vector3(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.z + (b.z - a.z) * t,
  );
}

/// Spherical linear interpolation between two quaternions.
Quaternion slerpQuaternion(Quaternion a, Quaternion b, double t) {
  // Ensure shortest path
  double dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
  Quaternion target = b;
  if (dot < 0) {
    target = Quaternion(-b.x, -b.y, -b.z, -b.w);
    dot = -dot;
  }

  if (dot > 0.9995) {
    // Very close — linear interpolation
    return Quaternion(
      a.x + (target.x - a.x) * t,
      a.y + (target.y - a.y) * t,
      a.z + (target.z - a.z) * t,
      a.w + (target.w - a.w) * t,
    )..normalize();
  }

  dot.clamp(-1.0, 1.0);
  final s0 = (1 - t);
  final s1 = t;

  return Quaternion(
    a.x * s0 + target.x * s1,
    a.y * s0 + target.y * s1,
    a.z * s0 + target.z * s1,
    a.w * s0 + target.w * s1,
  )..normalize();
}
