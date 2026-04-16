import 'package:vector_math/vector_math.dart';

import '../scene/node.dart';
import 'keyframe.dart';

/// A track that animates a single property of a node.
abstract class AnimationTrack {
  String get targetProperty;
  double get duration;
  void apply(Node node, double time);
}

/// Animates a Vector3 property (position, scale).
class Vector3Track extends AnimationTrack {
  final List<Keyframe<Vector3>> keyframes;

  @override
  final String targetProperty;

  Vector3Track({required this.targetProperty, required this.keyframes});

  @override
  double get duration => keyframes.isEmpty ? 0 : keyframes.last.time;

  @override
  void apply(Node node, double time) {
    final value = _evaluate(time);
    switch (targetProperty) {
      case 'position':
        node.transform.position = value;
        node.onTransformChanged();
      case 'scale':
        node.transform.scale = value;
        node.onTransformChanged();
    }
  }

  Vector3 _evaluate(double time) {
    if (keyframes.isEmpty) return Vector3.zero();
    if (keyframes.length == 1) return keyframes.first.value;

    // Clamp to range
    if (time <= keyframes.first.time) return keyframes.first.value;
    if (time >= keyframes.last.time) return keyframes.last.value;

    // Find surrounding keyframes
    for (var i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (time >= a.time && time <= b.time) {
        final localT = (time - a.time) / (b.time - a.time);
        final easedT = applyEasing(localT, b.easing);
        return lerpVector3(a.value, b.value, easedT);
      }
    }
    return keyframes.last.value;
  }
}

/// Animates a Quaternion property (rotation).
class QuaternionTrack extends AnimationTrack {
  final List<Keyframe<Quaternion>> keyframes;

  @override
  final String targetProperty;

  QuaternionTrack({this.targetProperty = 'rotation', required this.keyframes});

  @override
  double get duration => keyframes.isEmpty ? 0 : keyframes.last.time;

  @override
  void apply(Node node, double time) {
    final value = _evaluate(time);
    node.transform.rotation = value;
    node.onTransformChanged();
  }

  Quaternion _evaluate(double time) {
    if (keyframes.isEmpty) return Quaternion.identity();
    if (keyframes.length == 1) return keyframes.first.value;

    if (time <= keyframes.first.time) return keyframes.first.value;
    if (time >= keyframes.last.time) return keyframes.last.value;

    for (var i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (time >= a.time && time <= b.time) {
        final localT = (time - a.time) / (b.time - a.time);
        final easedT = applyEasing(localT, b.easing);
        return slerpQuaternion(a.value, b.value, easedT);
      }
    }
    return keyframes.last.value;
  }
}

/// A clip containing multiple tracks that animate a node.
class AnimationClip {
  final String name;
  final List<AnimationTrack> tracks;
  final bool loop;

  AnimationClip({required this.name, required this.tracks, this.loop = false});

  double get duration {
    double max = 0;
    for (final track in tracks) {
      if (track.duration > max) max = track.duration;
    }
    return max;
  }

  void apply(Node node, double time) {
    final t = (loop && duration > 0 ? time % duration : time.clamp(0, duration))
        .toDouble();
    for (final track in tracks) {
      track.apply(node, t);
    }
  }

  bool isFinished(double time) => !loop && time >= duration;
}
