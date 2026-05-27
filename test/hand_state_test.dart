import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('HandState', () {
    test('untracked hand has infinite pinch distance', () {
      final hand = HandState(hand: ControllerHand.left);
      expect(hand.pinchDistance, equals(double.infinity));
      expect(hand.isPinching, isFalse);
    });

    test('pinch detected when thumb and index tips are close', () {
      final hand = HandState(hand: ControllerHand.right, tracked: true);
      hand.joints[HandJoint.thumbTip] = Vector3(0, 0, 0);
      hand.joints[HandJoint.indexTip] = Vector3(0.01, 0, 0);

      expect(hand.isPinching, isTrue);
      expect(hand.pinchDistance, lessThan(0.02));
    });

    test('pinch NOT detected when tips are far apart', () {
      final hand = HandState(hand: ControllerHand.right, tracked: true);
      hand.joints[HandJoint.thumbTip] = Vector3(0, 0, 0);
      hand.joints[HandJoint.indexTip] = Vector3(0.1, 0, 0);

      expect(hand.isPinching, isFalse);
    });

    test('fist detected when all tips near palm', () {
      final hand = HandState(hand: ControllerHand.left, tracked: true);
      final palm = Vector3(0, 0, 0);
      hand.joints[HandJoint.palm] = palm;
      hand.joints[HandJoint.indexTip] = Vector3(0.03, 0, 0);
      hand.joints[HandJoint.middleTip] = Vector3(0, 0.03, 0);
      hand.joints[HandJoint.ringTip] = Vector3(-0.03, 0, 0);
      hand.joints[HandJoint.littleTip] = Vector3(0, -0.03, 0);

      expect(hand.isFist, isTrue);
    });

    test('fist NOT detected when one finger extended', () {
      final hand = HandState(hand: ControllerHand.left, tracked: true);
      final palm = Vector3(0, 0, 0);
      hand.joints[HandJoint.palm] = palm;
      hand.joints[HandJoint.indexTip] = Vector3(0.1, 0, 0); // Extended!
      hand.joints[HandJoint.middleTip] = Vector3(0.03, 0, 0);
      hand.joints[HandJoint.ringTip] = Vector3(-0.03, 0, 0);
      hand.joints[HandJoint.littleTip] = Vector3(0, -0.03, 0);

      expect(hand.isFist, isFalse);
    });

    test('pointing detected when index extended and others curled', () {
      final hand = HandState(hand: ControllerHand.right, tracked: true);
      hand.joints[HandJoint.palm] = Vector3(0, 0, 0);
      hand.joints[HandJoint.indexTip] = Vector3(0.1, 0, 0); // Extended
      hand.joints[HandJoint.middleTip] = Vector3(0.03, 0, 0); // Curled

      expect(hand.isPointing, isTrue);
    });

    test('pointingRay originates from index tip', () {
      final hand = HandState(hand: ControllerHand.right, tracked: true);
      hand.joints[HandJoint.palm] = Vector3(0, 0, 0);
      hand.joints[HandJoint.indexTip] = Vector3(0.1, 0, 0);

      final ray = hand.pointingRay;
      expect(ray, isNotNull);
      expect(ray!.origin.x, closeTo(0.1, 1e-4));
      // Direction should point away from palm
      expect(ray.direction.x, greaterThan(0));
    });

    test('all joints can be set and retrieved', () {
      final hand = HandState(hand: ControllerHand.left, tracked: true);

      for (final joint in HandJoint.values) {
        hand.joints[joint] = Vector3(joint.index.toDouble(), 0, 0);
      }

      expect(hand.joints.length, equals(HandJoint.values.length));
      expect(hand.joint(HandJoint.wrist)?.x, closeTo(1, 1e-6));
      expect(
        hand.joint(HandJoint.littleTip)?.x,
        closeTo(HandJoint.littleTip.index.toDouble(), 1e-6),
      );
    });

    test('flat hand detected when all tips are far from palm', () {
      final hand = HandState(hand: ControllerHand.left, tracked: true);
      hand.joints[HandJoint.palm] = Vector3(0, 0, 0);
      hand.joints[HandJoint.thumbTip] = Vector3(0.08, 0, 0);
      hand.joints[HandJoint.indexTip] = Vector3(0.08, 0.08, 0);
      hand.joints[HandJoint.middleTip] = Vector3(0, 0.09, 0);
      hand.joints[HandJoint.ringTip] = Vector3(-0.08, 0.08, 0);
      hand.joints[HandJoint.littleTip] = Vector3(-0.08, 0, 0);

      expect(hand.isFlatHand, isTrue);
    });

    test('thumbs up detected when thumb extended and others curled', () {
      final hand = HandState(hand: ControllerHand.left, tracked: true);
      hand.joints[HandJoint.palm] = Vector3(0, 0, 0);
      hand.joints[HandJoint.thumbTip] = Vector3(0.06, 0.06, 0); // Extended!
      hand.joints[HandJoint.indexTip] = Vector3(0.03, 0, 0);   // Curled
      hand.joints[HandJoint.middleTip] = Vector3(0, 0.03, 0);  // Curled
      hand.joints[HandJoint.ringTip] = Vector3(-0.03, 0, 0);   // Curled
      hand.joints[HandJoint.littleTip] = Vector3(0, -0.03, 0); // Curled

      expect(hand.isThumbsUp, isTrue);
    });

    test('victory detected when index and middle extended and others curled', () {
      final hand = HandState(hand: ControllerHand.left, tracked: true);
      hand.joints[HandJoint.palm] = Vector3(0, 0, 0);
      hand.joints[HandJoint.indexTip] = Vector3(0.08, 0.08, 0);  // Extended!
      hand.joints[HandJoint.middleTip] = Vector3(0, 0.09, 0);     // Extended!
      hand.joints[HandJoint.thumbTip] = Vector3(0.03, 0, 0);      // Curled
      hand.joints[HandJoint.ringTip] = Vector3(-0.03, 0, 0);      // Curled
      hand.joints[HandJoint.littleTip] = Vector3(0, -0.03, 0);    // Curled

      expect(hand.isVictory, isTrue);
      expect(hand.isFlatHand, isFalse);
    });

    test('orientations can be stored and retrieved', () {
      final hand = HandState(hand: ControllerHand.left, tracked: true);
      final q = Quaternion.axisAngle(Vector3(0, 1, 0), 1.0);
      hand.orientations[HandJoint.wrist] = q;

      expect(hand.jointOrientation(HandJoint.wrist), equals(q));
      expect(hand.jointOrientation(HandJoint.palm), isNull);
    });

    test('boneConnections list is populated with 25 connections', () {
      expect(HandState.boneConnections.length, equals(25));
      expect(HandState.boneConnections.first.parent, equals(HandJoint.wrist));
      expect(HandState.boneConnections.first.child, equals(HandJoint.palm));
    });
  });

  group('ControllerState', () {
    test('ray points in forward direction', () {
      final controller = ControllerState(hand: ControllerHand.right);
      controller.transform.position = Vector3(0, 1, 0);

      final ray = controller.ray;
      expect(ray.origin.y, closeTo(1, 1e-6));
      // Default forward is (0, 0, -1) for identity rotation
      expect(ray.direction.z, closeTo(-1, 1e-4));
    });

    test('reset clears all inputs', () {
      final controller = ControllerState(hand: ControllerHand.left);
      controller.triggerPressed = true;
      controller.triggerValue = 0.8;
      controller.gripPressed = true;
      controller.primaryButtonPressed = true;
      controller.thumbstick = Vector2(0.5, -0.3);

      controller.reset();

      expect(controller.triggerPressed, isFalse);
      expect(controller.triggerValue, closeTo(0, 1e-6));
      expect(controller.gripPressed, isFalse);
      expect(controller.thumbstick.length, closeTo(0, 1e-6));
    });
  });
}
