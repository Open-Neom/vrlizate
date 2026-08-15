import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

/// Builds 21 MediaPipe-ordered landmarks for a synthetic open hand centered
/// at (0.5, 0.5) in normalized image space.
List<Vector3> syntheticHand({double pinchGap = 0.1, double spread = 0.3}) {
  final lm = List<Vector3>.generate(21, (i) => Vector3(0.5, 0.5, 0));
  // Wrist.
  lm[0] = Vector3(0.5, 0.8, 0);
  // Thumb chain (landmarks 1-4), tip near index tip when pinchGap is small.
  lm[1] = Vector3(0.45, 0.7, 0);
  lm[2] = Vector3(0.42, 0.62, 0);
  lm[3] = Vector3(0.40, 0.55, 0);
  lm[4] = Vector3(0.5 - pinchGap / 2, 0.30, 0); // Thumb tip.
  // Index chain (5-8), tip at the other side of the pinch gap.
  lm[5] = Vector3(0.47, 0.55, 0);
  lm[6] = Vector3(0.48, 0.45, 0);
  lm[7] = Vector3(0.49, 0.37, 0);
  lm[8] = Vector3(0.5 + pinchGap / 2, 0.30, 0); // Index tip.
  // Middle / ring / little spread out.
  lm[9] = Vector3(0.53, 0.55, 0);
  lm[12] = Vector3(0.55, 0.30 - spread * 0.1, 0);
  lm[13] = Vector3(0.58, 0.56, 0);
  lm[16] = Vector3(0.60, 0.32, 0);
  lm[17] = Vector3(0.62, 0.58, 0);
  lm[20] = Vector3(0.65, 0.36, 0);
  return lm;
}

void main() {
  group('CameraHandTrackingDriver', () {
    test('updates HandState from real frames and marks it tracked', () {
      final driver = CameraHandTrackingDriver();
      HandState? updated;
      driver.onHandUpdated = (hand, state) => updated = state;

      driver.feedFrame(
        HandLandmarkFrame(
          landmarks: syntheticHand(),
          hand: ControllerHand.right,
        ),
      );

      expect(updated, isNotNull);
      expect(driver.hands[ControllerHand.right]!.tracked, isTrue);
      expect(driver.hands[ControllerHand.left]!.tracked, isFalse);

      // Wrist (image y=0.8) must project to metric space: y negative-down
      // flip maps (0.8-0.5)*0.35 -> -0.105.
      final wrist = driver.hands[ControllerHand.right]!.joint(HandJoint.wrist)!;
      expect(wrist.y, closeTo(-0.105, 1e-3));
      expect(wrist.z, closeTo(-0.35, 1e-3));
      driver.dispose();
    });

    test('drops frames below the confidence threshold', () {
      final driver = CameraHandTrackingDriver(minConfidence: 0.6);
      driver.feedFrame(
        HandLandmarkFrame(
          landmarks: syntheticHand(),
          hand: ControllerHand.left,
          confidence: 0.4,
        ),
      );
      expect(driver.hands[ControllerHand.left]!.tracked, isFalse);
      driver.dispose();
    });

    test('marks hand as lost after trackingTimeout without frames', () {
      final driver = CameraHandTrackingDriver(
        trackingTimeout: const Duration(milliseconds: 50),
      );
      ControllerHand? lost;
      driver.onHandLost = (hand) => lost = hand;

      // Frame with an old timestamp: the next update() sees it as stale.
      driver.feedFrame(
        HandLandmarkFrame(
          landmarks: syntheticHand(),
          hand: ControllerHand.right,
          timestamp: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      driver.update();

      expect(lost, ControllerHand.right);
      expect(driver.hands[ControllerHand.right]!.tracked, isFalse);
      driver.dispose();
    });

    test('One Euro filter smooths jitter but follows real motion', () {
      final filter = OneEuroFilter(minCutoff: 1.0, beta: 0.05);
      final t0 = DateTime(2026, 1, 1);

      // Steady signal with noise: output stays close to the mean.
      var last = Vector3.zero();
      for (var i = 0; i < 60; i++) {
        final noisy = Vector3(0.01 * (i.isEven ? 1 : -1), 0, 0);
        last = filter.filter(noisy, t0.add(Duration(milliseconds: i * 16)));
      }
      expect(last.x.abs(), lessThan(0.01));

      // Fast step motion: output converges quickly (low lag).
      filter.reset();
      filter.filter(Vector3.zero(), t0);
      for (var i = 1; i < 30; i++) {
        last = filter.filter(
          Vector3(1, 0, 0),
          t0.add(Duration(milliseconds: i * 16)),
        );
      }
      expect(last.x, greaterThan(0.8));
    });
  });

  group('HandGestureRecognizer', () {
    HandState pinchingHand() {
      final state = HandState(hand: ControllerHand.right);
      // Pinch: thumb tip and index tip 1 cm apart (metric space).
      MediaPipeHandDriver.updateHandFromLandmarks(
        state,
        // Reuse the driver with metric-scale landmarks: build a synthetic
        // hand directly in meters around origin.
        List<Vector3>.generate(21, (i) => Vector3(0, 0.1, -0.35))
          ..[4] =
              Vector3(0.005, 0.2, -0.35) // thumb tip
          ..[8] = Vector3(-0.005, 0.2, -0.35), // index tip
      );
      return state;
    }

    test('pinch fires start/end edges immediately', () {
      final recognizer = HandGestureRecognizer();
      final events = <HandGesture>[];
      recognizer.onGesture = (e) => events.add(e.gesture);

      final state = pinchingHand();
      recognizer.evaluate(ControllerHand.right, state);
      expect(events, [HandGesture.pinchStart]);

      // Release: move thumb tip far from index tip.
      state.joints[HandJoint.thumbTip] = Vector3(0.2, 0.1, -0.35);
      recognizer.evaluate(ControllerHand.right, state);
      expect(events, [HandGesture.pinchStart, HandGesture.pinchEnd]);
      recognizer.dispose();
    });

    test('level gestures are debounced by minHoldDuration', () async {
      final recognizer = HandGestureRecognizer(
        minHoldDuration: const Duration(milliseconds: 60),
      );
      final events = <HandGesture>[];
      recognizer.onGesture = (e) => events.add(e.gesture);

      // Build a fist in metric space: all tips within 5 cm of the palm,
      // but thumb and index tips 8 cm apart so it is not a pinch.
      final fist = HandState(hand: ControllerHand.left);
      MediaPipeHandDriver.updateHandFromLandmarks(
        fist,
        List<Vector3>.generate(21, (i) => Vector3(0, 0, -0.35))
          ..[4] =
              Vector3(0.04, 0, -0.35) // thumb tip
          ..[8] = Vector3(-0.04, 0, -0.35), // index tip
      );

      recognizer.evaluate(ControllerHand.left, fist); // pending
      expect(events, isEmpty);

      await Future.delayed(const Duration(milliseconds: 70));
      recognizer.evaluate(ControllerHand.left, fist); // confirmed
      expect(events, [HandGesture.fist]);
      recognizer.dispose();
    });

    test('lost tracking clears pending and active gestures', () {
      final recognizer = HandGestureRecognizer();
      final events = <HandGesture>[];
      recognizer.onGesture = (e) => events.add(e.gesture);

      final state = pinchingHand();
      recognizer.evaluate(ControllerHand.right, state);
      expect(events, [HandGesture.pinchStart]);

      state.tracked = false;
      recognizer.evaluate(ControllerHand.right, state);
      expect(events, [HandGesture.pinchStart, HandGesture.pinchEnd]);
      recognizer.dispose();
    });
  });
}
