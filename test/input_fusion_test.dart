import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InputFusion', () {
    test('gaze dwell emits a SelectAction with the target id', () async {
      final gaze = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 0.5,
        adaptiveDwell: false,
      );
      final fusion = InputFusion(gazePointer: gaze);
      final actions = <VrInputAction>[];
      final sub = fusion.onAction.listen(actions.add);

      gaze.update(0.01, 'button-1');
      gaze.update(0.6, 'button-1');
      await Future.delayed(Duration.zero);

      expect(actions, hasLength(1));
      final action = actions.first as SelectAction;
      expect(action.targetId, 'button-1');
      expect(action.source, 'gaze');

      await sub.cancel();
      fusion.dispose();
    });

    test('hand pinch emits a SelectAction from the hand channel', () async {
      final recognizer = HandGestureRecognizer();
      final fusion = InputFusion(gestureRecognizer: recognizer);
      final actions = <VrInputAction>[];
      final sub = fusion.onAction.listen(actions.add);

      final state = HandState(hand: ControllerHand.right);
      MediaPipeHandDriver.updateHandFromLandmarks(
        state,
        List<Vector3>.generate(21, (i) => Vector3(0, 0.1, -0.35))
          ..[4] = Vector3(0.005, 0.2, -0.35)
          ..[8] = Vector3(-0.005, 0.2, -0.35),
      );
      recognizer.evaluate(ControllerHand.right, state);
      await Future.delayed(Duration.zero);

      final selects = actions.whereType<SelectAction>().toList();
      expect(selects, hasLength(1));
      expect(selects.first.source, 'hand');

      await sub.cancel();
      fusion.dispose();
    });

    test('select cooldown merges rapid selections from any channel', () async {
      final gaze = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 0.2,
        adaptiveDwell: false,
      );
      final fusion = InputFusion(
        gazePointer: gaze,
        selectCooldown: const Duration(seconds: 2),
      );
      final actions = <VrInputAction>[];
      final sub = fusion.onAction.listen(actions.add);

      gaze.update(0.01, 'a');
      gaze.update(0.3, 'a');
      gaze.update(0.3, null);
      gaze.update(0.01, 'b');
      gaze.update(0.3, 'b');
      await Future.delayed(Duration.zero);

      final selects = actions.whereType<SelectAction>().toList();
      expect(selects, hasLength(1));
      expect(selects.first.targetId, 'a');

      await sub.cancel();
      fusion.dispose();
    });

    test('fist gesture maps to BackAction', () async {
      final recognizer = HandGestureRecognizer(minHoldDuration: Duration.zero);
      final fusion = InputFusion(gestureRecognizer: recognizer);
      final actions = <VrInputAction>[];
      final sub = fusion.onAction.listen(actions.add);

      final fist = HandState(hand: ControllerHand.left);
      MediaPipeHandDriver.updateHandFromLandmarks(
        fist,
        List<Vector3>.generate(21, (i) => Vector3(0, 0, -0.35))
          ..[4] = Vector3(0.04, 0, -0.35)
          ..[8] = Vector3(-0.04, 0, -0.35),
      );
      recognizer.evaluate(ControllerHand.left, fist);
      recognizer.evaluate(ControllerHand.left, fist); // confirm debounce
      await Future.delayed(Duration.zero);

      expect(actions.whereType<BackAction>(), hasLength(1));

      await sub.cancel();
      fusion.dispose();
    });

    test('walk-in-place cadence produces MoveActions', () async {
      final detector = WalkInPlaceDetector(
        stepThreshold: 1.0,
        refractoryPeriod: const Duration(milliseconds: 250),
      );
      final fusion = InputFusion(walkInPlace: detector);
      final actions = <VrInputAction>[];
      final sub = fusion.onAction.listen(actions.add);

      detector.reset();
      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 150; i++) {
        final t = i / 50.0;
        final bob = 2.5 * math.sin(2 * math.pi * 2.0 * t);
        detector.feedSample(
          0,
          0,
          -9.8 + bob,
          t0.add(Duration(milliseconds: i * 20)),
        );
        fusion.update(0.02);
      }
      await Future.delayed(Duration.zero);

      final moves = actions.whereType<MoveAction>().toList();
      expect(moves, isNotEmpty);
      expect(moves.last.speed, greaterThan(0.5));

      await sub.cancel();
      fusion.dispose();
      detector.dispose();
    });

    test('ultrasonic push selects the current gaze target', () async {
      final gaze = GazePointer(cameraRig: CameraRig(), adaptiveDwell: false);
      final ultrasonic = UltrasonicGestureChannel();
      final fusion = InputFusion(gazePointer: gaze, ultrasonic: ultrasonic);
      final actions = <VrInputAction>[];
      final sub = fusion.onAction.listen(actions.add);

      gaze.update(0.01, 'door'); // gaze rests on a target
      ultrasonic.onGesture?.call(
        UltrasonicGestureEvent(gesture: UltrasonicGesture.push),
      );
      await Future.delayed(Duration.zero);

      final selects = actions.whereType<SelectAction>().toList();
      expect(selects, hasLength(1));
      expect(selects.first.source, 'ultrasonic');
      expect(selects.first.targetId, 'door');

      await sub.cancel();
      fusion.dispose();
    });

    test('ultrasonic pull maps to BackAction', () async {
      final ultrasonic = UltrasonicGestureChannel();
      final fusion = InputFusion(ultrasonic: ultrasonic);
      final actions = <VrInputAction>[];
      final sub = fusion.onAction.listen(actions.add);

      ultrasonic.onGesture?.call(
        UltrasonicGestureEvent(gesture: UltrasonicGesture.pull),
      );
      await Future.delayed(Duration.zero);

      expect(actions.whereType<BackAction>(), hasLength(1));

      await sub.cancel();
      fusion.dispose();
    });
  });
}
