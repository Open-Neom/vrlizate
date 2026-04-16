import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('Animation', () {
    test('Vector3Track interpolates between keyframes', () {
      final node = Node(name: 'target');
      final track = Vector3Track(
        targetProperty: 'position',
        keyframes: [
          Keyframe(time: 0, value: Vector3(0, 0, 0)),
          Keyframe(time: 1, value: Vector3(10, 0, 0)),
        ],
      );

      track.apply(node, 0.5);
      expect(node.transform.position.x, closeTo(5, 1e-4));
    });

    test('Vector3Track clamps before first keyframe', () {
      final node = Node(name: 'target');
      final track = Vector3Track(
        targetProperty: 'position',
        keyframes: [
          Keyframe(time: 1, value: Vector3(0, 0, 0)),
          Keyframe(time: 2, value: Vector3(10, 0, 0)),
        ],
      );

      track.apply(node, 0); // Before first keyframe
      expect(node.transform.position.x, closeTo(0, 1e-4));
    });

    test('Vector3Track clamps after last keyframe', () {
      final node = Node(name: 'target');
      final track = Vector3Track(
        targetProperty: 'position',
        keyframes: [
          Keyframe(time: 0, value: Vector3(0, 0, 0)),
          Keyframe(time: 1, value: Vector3(10, 0, 0)),
        ],
      );

      track.apply(node, 5); // Way past end
      expect(node.transform.position.x, closeTo(10, 1e-4));
    });

    test('AnimationClip loop wraps time', () {
      final node = Node(name: 'target');
      final clip = AnimationClip(
        name: 'test',
        loop: true,
        tracks: [
          Vector3Track(
            targetProperty: 'position',
            keyframes: [
              Keyframe(time: 0, value: Vector3(0, 0, 0)),
              Keyframe(time: 1, value: Vector3(10, 0, 0)),
            ],
          ),
        ],
      );

      clip.apply(node, 0.5);
      expect(node.transform.position.x, closeTo(5, 1e-4));

      clip.apply(node, 1.5); // Loops back to 0.5
      expect(node.transform.position.x, closeTo(5, 1e-4));
    });

    test('AnimationClip isFinished works for non-loop', () {
      final clip = AnimationClip(
        name: 'test',
        loop: false,
        tracks: [
          Vector3Track(
            targetProperty: 'position',
            keyframes: [
              Keyframe(time: 0, value: Vector3.zero()),
              Keyframe(time: 2, value: Vector3(1, 0, 0)),
            ],
          ),
        ],
      );

      expect(clip.isFinished(1), isFalse);
      expect(clip.isFinished(2), isTrue);
      expect(clip.isFinished(3), isTrue);
    });

    test('AnimationMixer plays and advances', () {
      final node = Node(name: 'target');
      final mixer = AnimationMixer(target: node);

      final clip = AnimationClip(
        name: 'move',
        tracks: [
          Vector3Track(
            targetProperty: 'position',
            keyframes: [
              Keyframe(time: 0, value: Vector3.zero()),
              Keyframe(time: 1, value: Vector3(10, 0, 0)),
            ],
          ),
        ],
      );

      mixer.play(clip);
      expect(mixer.isPlaying, isTrue);

      mixer.update(0.5); // Advance half second
      expect(node.transform.position.x, closeTo(5, 1e-4));

      mixer.update(0.6); // Past duration
      expect(mixer.isPlaying, isFalse); // Non-looping clip finished
    });

    test('AnimationPlayback pause/resume works', () {
      final node = Node(name: 'target');
      final mixer = AnimationMixer(target: node);

      final clip = AnimationClip(
        name: 'move',
        loop: true,
        tracks: [
          Vector3Track(
            targetProperty: 'position',
            keyframes: [
              Keyframe(time: 0, value: Vector3.zero()),
              Keyframe(time: 1, value: Vector3(10, 0, 0)),
            ],
          ),
        ],
      );

      final playback = mixer.play(clip);
      mixer.update(0.3);
      final posAtPause = node.transform.position.x;

      playback.pause();
      mixer.update(0.5); // Should not advance

      expect(node.transform.position.x, closeTo(posAtPause, 1e-4));

      playback.resume();
      mixer.update(0.1);
      expect(node.transform.position.x, greaterThan(posAtPause));
    });

    test('SLERP produces unit quaternion', () {
      final a = Quaternion.identity();
      final b = Quaternion.axisAngle(Vector3(0, 1, 0), 1.5);

      for (var t = 0.0; t <= 1.0; t += 0.1) {
        final result = slerpQuaternion(a, b, t);
        expect(result.length, closeTo(1.0, 1e-4));
      }
    });

    test('easing functions return 0 at t=0 and 1 at t=1', () {
      for (final easing in EasingFunction.values) {
        expect(applyEasing(0, easing), closeTo(0, 1e-2));
        expect(applyEasing(1, easing), closeTo(1, 1e-2));
      }
    });
  });
}
