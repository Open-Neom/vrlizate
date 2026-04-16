import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

/// Animation system benchmarks — skeleton evaluation, clip playback,
/// mixer blending, and keyframe interpolation at scale.
void main() {
  group('Animation — Stress', () {
    test('humanoid skeleton: all bones produce valid skinning matrices', () {
      final skeleton = Skeleton.humanoid();

      expect(skeleton.bones.length, greaterThanOrEqualTo(15));

      final matrices = skeleton.skinningMatrices;
      for (final m in matrices) {
        for (var i = 0; i < 16; i++) {
          expect(m.storage[i].isNaN, isFalse);
        }
      }
    });

    test('bone lookup by name finds all humanoid bones', () {
      final skeleton = Skeleton.humanoid();
      final expectedBones = [
        'hip', 'spine', 'neck', 'head',
        'leftShoulder', 'leftElbow', 'leftHand',
        'rightShoulder', 'rightElbow', 'rightHand',
        'leftHip', 'leftKnee', 'leftFoot',
        'rightHip', 'rightKnee', 'rightFoot',
      ];

      for (final name in expectedBones) {
        expect(skeleton.findBone(name), isNotNull,
          reason: 'Bone "$name" not found');
      }
    });

    test('animation mixer blends 10 clips without overflow', () {
      final target = Node(name: 'animated');
      final mixer = AnimationMixer(target: target);

      for (var i = 0; i < 10; i++) {
        final clip = AnimationClip(
          name: 'clip_$i',
          tracks: [
            Vector3Track(
              targetProperty: 'position',
              keyframes: [
                Keyframe<Vector3>(time: 0, value: Vector3.zero()),
                Keyframe<Vector3>(time: 1, value: Vector3(i.toDouble(), 0, 0)),
                Keyframe<Vector3>(time: 2, value: Vector3.zero()),
              ],
            ),
          ],
          loop: true,
        );

        mixer.play(clip, weight: 0.1);
      }

      expect(mixer.activeClipCount, equals(10));

      for (var i = 0; i < 1000; i++) {
        mixer.update(1 / 60);
      }

      expect(mixer.activeClipCount, equals(10));
    });

    test('non-looping clip auto-finishes', () {
      final clip = AnimationClip(
        name: 'oneshot',
        tracks: [
          Vector3Track(
            targetProperty: 'position',
            keyframes: [
              Keyframe<Vector3>(time: 0, value: Vector3.zero()),
              Keyframe<Vector3>(time: 1, value: Vector3(1, 0, 0)),
            ],
          ),
        ],
        loop: false,
      );

      final mixer = AnimationMixer(target: Node(name: 'n'));
      final handle = mixer.play(clip);

      for (var i = 0; i < 120; i++) {
        mixer.update(1 / 60);
      }

      expect(handle.isFinished, isTrue);
    });

    test('Vector3Track interpolation is smooth', () {
      final track = Vector3Track(
        targetProperty: 'position',
        keyframes: [
          Keyframe<Vector3>(time: 0, value: Vector3(0, 0, 0)),
          Keyframe<Vector3>(time: 1, value: Vector3(10, 0, 0)),
        ],
      );

      // Manually evaluate by creating a node and clip
      final clip = AnimationClip(name: 'test', tracks: [track]);
      final node = Node(name: 'target');

      clip.apply(node, 0);
      expect(node.transform.position.x, closeTo(0, 1e-3));

      clip.apply(node, 0.5);
      expect(node.transform.position.x, closeTo(5, 1e-3));

      clip.apply(node, 1.0);
      expect(node.transform.position.x, closeTo(10, 1e-3));
    });

    test('easing functions are bounded [0, 1]', () {
      final easings = [
        EasingFunction.linear,
        EasingFunction.easeIn,
        EasingFunction.easeOut,
        EasingFunction.easeInOut,
      ];

      for (final ease in easings) {
        expect(applyEasing(0, ease), closeTo(0, 1e-6));
        expect(applyEasing(1, ease), closeTo(1, 1e-6));
      }
    });
  });
}
