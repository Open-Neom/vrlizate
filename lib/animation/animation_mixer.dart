import '../scene/node.dart';
import 'animation_clip.dart';

/// Plays and blends multiple animation clips on a node.
class AnimationMixer {
  final Node target;
  final List<_ActiveClip> _activeClips = [];

  AnimationMixer({required this.target});

  /// Plays a clip. If [weight] < 1, blends with other active clips.
  AnimationPlayback play(
    AnimationClip clip, {
    double weight = 1.0,
    double speed = 1.0,
  }) {
    final active = _ActiveClip(clip: clip, weight: weight, speed: speed);
    _activeClips.add(active);
    return AnimationPlayback._(active);
  }

  /// Stops all clips with the given name.
  void stop(String clipName) {
    _activeClips.removeWhere((a) => a.clip.name == clipName);
  }

  /// Stops all clips.
  void stopAll() {
    _activeClips.clear();
  }

  /// Call each frame to advance and apply all active animations.
  void update(double dt) {
    final toRemove = <_ActiveClip>[];

    for (final active in _activeClips) {
      if (active.paused) continue;
      active.time += dt * active.speed;

      if (active.clip.isFinished(active.time)) {
        active.clip.apply(target, active.clip.duration);
        if (!active.clip.loop) toRemove.add(active);
        continue;
      }

      active.clip.apply(target, active.time);
    }

    _activeClips.removeWhere((a) => toRemove.contains(a));
  }

  bool get isPlaying => _activeClips.isNotEmpty;
  int get activeClipCount => _activeClips.length;
}

class _ActiveClip {
  final AnimationClip clip;
  double weight;
  double speed;
  double time = 0;
  bool paused = false;

  _ActiveClip({required this.clip, this.weight = 1.0, this.speed = 1.0});
}

/// Handle to control a playing animation.
class AnimationPlayback {
  final _ActiveClip _clip;
  AnimationPlayback._(this._clip);

  double get time => _clip.time;
  set time(double t) => _clip.time = t;

  double get speed => _clip.speed;
  set speed(double s) => _clip.speed = s;

  double get weight => _clip.weight;
  set weight(double w) => _clip.weight = w;

  bool get paused => _clip.paused;
  void pause() => _clip.paused = true;
  void resume() => _clip.paused = false;

  bool get isFinished => _clip.clip.isFinished(_clip.time);
}
