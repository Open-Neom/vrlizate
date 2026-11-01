import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('VrOpticalZoomCurve (0.6x Eyefish <-> 100x Space Zoom)', () {
    test('maps normalized 0..1 logarithmically across 0.6x..100x S25 Ultra range', () {
      const minZ = 0.6;
      const maxZ = 100.0;

      expect(
        VrOpticalZoomCurve.normalizedToZoomRatio(0.0, minZoom: minZ, maxZoom: maxZ),
        closeTo(0.6, 1e-6),
      );
      expect(
        VrOpticalZoomCurve.normalizedToZoomRatio(1.0, minZoom: minZ, maxZoom: maxZ),
        closeTo(100.0, 1e-5),
      );

      // Midpoint t=0.5 in log space is sqrt(0.6 * 100) ≈ 7.746x (smooth optical transition!)
      final midZoom = VrOpticalZoomCurve.normalizedToZoomRatio(
        0.5,
        minZoom: minZ,
        maxZoom: maxZ,
      );
      expect(midZoom, closeTo(7.745966, 1e-3));

      // Round-trip inverse accuracy
      for (final z in <double>[0.6, 1.0, 3.0, 10.0, 30.0, 100.0]) {
        final norm = VrOpticalZoomCurve.zoomRatioToNormalized(
          z,
          minZoom: minZ,
          maxZoom: maxZ,
        );
        final restored = VrOpticalZoomCurve.normalizedToZoomRatio(
          norm,
          minZoom: minZ,
          maxZoom: maxZ,
        );
        expect(restored, closeTo(z, 1e-4));
      }
    });
  });

  group('VrEMudraEngine — Cyberneom eMudras & Tri-Camera Multi-View Fusion', () {
    test('Tri-Camera consensus boosts confidence above single occluded camera', () {
      final engine = VrEMudraEngine(activationConfirmFrames: 1);
      final gyanRight = VrHandMudraSignature.fromCoarsePose(
        hand: ControllerHand.right,
        isPinching: true,
        depthMeters: 0.48,
      );

      // Single Joystick camera at moderate confidence (0.58 * 0.84 = 0.487)
      final singleState = engine.fuseObservations([
        VrEMudraCameraObservation(
          cameraRole: VrEMudraCameraRole.joystickUpward,
          confidence: 0.58,
          rightHand: gyanRight,
        ),
      ]);
      expect(singleState.activeMudra, VrCanonicalEMudra.gyanConfirm);
      expect(singleState.isMultiCameraVerified, isFalse);

      // Tri-Camera agreement (Visor Ultra-Wide + Joystick Upward + PC Estación Faro)
      final triState = engine.fuseObservations([
        VrEMudraCameraObservation(
          cameraRole: VrEMudraCameraRole.visorUltraWide,
          confidence: 0.62,
          rightHand: gyanRight,
        ),
        VrEMudraCameraObservation(
          cameraRole: VrEMudraCameraRole.joystickUpward,
          confidence: 0.58,
          rightHand: gyanRight,
        ),
        VrEMudraCameraObservation(
          cameraRole: VrEMudraCameraRole.desktopFaro,
          confidence: 0.68,
          rightHand: gyanRight,
        ),
      ]);

      expect(triState.activeMudra, VrCanonicalEMudra.gyanConfirm);
      expect(triState.isTriCameraVerified, isTrue);
      expect(triState.fusedConfidence, greaterThan(singleState.fusedConfidence + 0.35));
      expect(triState.fusedConfidence, greaterThan(0.90));
      expect(triState.toInputEvent()?.type, VrInputType.select);
    });

    test('Prana Telescope eMudra sweeps S25 zoom smoothly from 0.6x to 100x', () {
      final engine = VrEMudraEngine(
        activationConfirmFrames: 1,
        zoomSmoothingAlpha: 1.0,
      );
      final leftPinch = VrHandMudraSignature.fromCoarsePose(
        hand: ControllerHand.left,
        isPinching: true,
      );
      final rightPinch = VrHandMudraSignature.fromCoarsePose(
        hand: ControllerHand.right,
        isPinching: true,
      );

      // Narrow span (0.08 m) -> 0.6x Ultra-Wide / Eyefish
      final narrow = engine.fuseObservations(
        [
          VrEMudraCameraObservation(
            cameraRole: VrEMudraCameraRole.desktopFaro,
            confidence: 0.85,
            leftHand: leftPinch,
            rightHand: rightPinch,
            bimanualSpanMeters: 0.08,
          ),
        ],
        minZoomRatio: 0.6,
        maxZoomRatio: 100.0,
      );
      expect(narrow.activeMudra, VrCanonicalEMudra.pranaTelescopeZoom);
      expect(narrow.targetZoomRatio, closeTo(0.6, 1e-3));

      // Wide bimanual span (0.52 m) -> 100x Space Zoom
      final wide = engine.fuseObservations(
        [
          VrEMudraCameraObservation(
            cameraRole: VrEMudraCameraRole.desktopFaro,
            confidence: 0.85,
            leftHand: leftPinch,
            rightHand: rightPinch,
            bimanualSpanMeters: 0.52,
          ),
        ],
        minZoomRatio: 0.6,
        maxZoomRatio: 100.0,
      );
      expect(wide.activeMudra, VrCanonicalEMudra.pranaTelescopeZoom);
      expect(wide.targetZoomRatio, closeTo(100.0, 1e-2));
    });

    test('supports custom combinatorial Cyberneom eMudra registration', () {
      final engine = VrEMudraEngine(activationConfirmFrames: 1);
      engine.registerCustomMudra(
        const VrCustomEMudraBinding(
          id: 'kryptos_triad',
          displayName: 'Sintonía del Verbo',
          rightPatternCode: 'R:E-A-E-F-E@idx',
          commandAction: 'invoke_saia_portal',
        ),
      );

      const customRight = VrHandMudraSignature(
        hand: ControllerHand.right,
        thumb: VrDigitCurlState.extended,
        index: VrDigitCurlState.arched,
        middle: VrDigitCurlState.extended,
        ring: VrDigitCurlState.folded,
        little: VrDigitCurlState.extended,
        thumbContact: VrThumbContactChannel.indexTip,
      );

      final res = engine.fuseObservations([
        const VrEMudraCameraObservation(
          cameraRole: VrEMudraCameraRole.visorUltraWide,
          confidence: 0.80,
          rightHand: customRight,
        ),
      ]);
      expect(res.activeMudra, VrCanonicalEMudra.custom);
      expect(res.customMudraId, 'kryptos_triad');
    });

    test('extracts Akash mudra from 26-joint OpenXR HandState', () {
      final hand = HandState(
        hand: ControllerHand.right,
        tracked: true,
        joints: {
          HandJoint.wrist: Vector3(0, -0.06, -0.45),
          HandJoint.palm: Vector3(0, 0, -0.45),
          HandJoint.indexProximal: Vector3(-0.02, 0.03, -0.45),
          HandJoint.littleProximal: Vector3(0.02, 0.03, -0.45),
          // Thumb + Middle touching (Akash Mudra)
          HandJoint.thumbTip: Vector3(0.0, 0.055, -0.46),
          HandJoint.middleTip: Vector3(0.005, 0.058, -0.46),
          // Index, Ring, Little extended
          HandJoint.indexTip: Vector3(-0.02, 0.088, -0.45),
          HandJoint.ringTip: Vector3(0.015, 0.085, -0.45),
          HandJoint.littleTip: Vector3(0.03, 0.075, -0.45),
        },
      );
      final sig = VrHandMudraSignature.fromHandState(hand);
      expect(sig.thumbContact, VrThumbContactChannel.middleTip);
      expect(sig.isAkashLike, isTrue);
    });
  });

  group('Low-Latency 1-Euro Filter, Hand ROI & Lazy-Wakeup Schedule', () {
    test('VrOneEuroFilter suppresses micro-tremor at rest and tracks fast sweeps', () {
      final filter = VrOneEuroFilter(minCutoffHz: 0.90, beta: 5.2);
      filter.filter(0.50, dtSeconds: 1 / 60);
      // Tiny hand tremor (+0.003) is heavily damped
      final steady = filter.filter(0.503, dtSeconds: 1 / 60);
      expect((steady - 0.50).abs(), lessThan(0.0008));

      // Fast intentional sweep (0.50 -> 0.95) opens bandwidth + lookahead immediately
      final fast = filter.filter(
        0.95,
        dtSeconds: 1 / 60,
        lookaheadSeconds: 0.018,
      );
      expect(fast, greaterThan(0.82));
    });

    test('VrHandRoiBounds cuts >57% visor pixels and ~75% desktop pixels', () {
      expect(
        VrHandRoiBounds.visorFrontalHeadsetRoi.savedPixelFraction,
        greaterThan(0.57),
      );
      expect(
        VrHandRoiBounds.visorFrontalHeadsetRoi.containsUv(0.50, 0.62),
        isTrue,
      );
      // Ceiling / top 15% of Ultra-Wide lens is ignored
      expect(
        VrHandRoiBounds.visorFrontalHeadsetRoi.containsUv(0.50, 0.12),
        isFalse,
      );

      final desktopRoi = VrHandRoiBounds.desktopTorsoAnchored();
      expect(desktopRoi.savedPixelFraction, closeTo(0.748, 0.01));
    });

    test('VrTriCameraSensingSchedule hibernates mobile CV on PC lock and sheds >1.8x zoom', () {
      // 1. PC sees hands clearly (0.90) & user faces desk -> both mobile CV streams 0 Hz!
      final pcPrimary = VrTriCameraSensingSchedule.compute(
        beaconConnected: true,
        desktopHandConfidence: 0.90,
        headYawFromDesktopRadians: 0.10,
        visorZoomRatio: 0.6,
        visorCameraActive: true,
      );
      expect(pcPrimary.runDesktopVision, isTrue);
      expect(pcPrimary.runJoystickPalmarAssist, isFalse);
      expect(pcPrimary.runVisorCvStream, isFalse);
      expect(pcPrimary.visorAnalysisIntervalMs, 0);

      // 2. User turns >75 deg away from PC (1.55 rad) -> wakes local Visor ROI at 66 ms
      final turnedAway = VrTriCameraSensingSchedule.compute(
        beaconConnected: true,
        desktopHandConfidence: 0.90,
        headYawFromDesktopRadians: 1.55,
        visorZoomRatio: 0.6,
        visorCameraActive: true,
      );
      expect(turnedAway.runVisorCvStream, isTrue);
      expect(turnedAway.visorAnalysisIntervalMs, 66);

      // 3. S25 Ultra zoomed to 30x Space Zoom -> Visor CV stream strictly shed to 0 Hz!
      final zoomed30x = VrTriCameraSensingSchedule.compute(
        beaconConnected: false,
        desktopHandConfidence: 0.0,
        headYawFromDesktopRadians: 0.0,
        visorZoomRatio: 30.0,
        visorCameraActive: true,
      );
      expect(zoomed30x.runVisorCvStream, isFalse);
      expect(zoomed30x.runJoystickPalmarAssist, isTrue);
    });
  });
}
