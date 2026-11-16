import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('CameraDistortionIntrinsics (Brown-Conrady + 2x2 Newton-Raphson)', () {
    test('inverts radial and tangential wide-angle distortion to sub-thousandth pixel', () {
      final intrinsics = CameraDistortionIntrinsics.fromHorizontalFov(
        widthPx: 1280,
        heightPx: 720,
        horizontalFovDegrees: 84.0,
        k1: -0.26,
        k2: 0.095,
        p1: 0.0035,
        p2: -0.0028,
      );

      final testRays = <Vector3>[
        Vector3(0.0, 0.0, 1.4),
        Vector3(0.55, -0.32, 1.2),
        Vector3(-0.68, 0.38, 1.35),
        Vector3(0.42, 0.29, 0.95),
      ];

      for (final pCam in testRays) {
        final px = intrinsics.projectCameraPoint(pCam);
        final recoveredNorm = intrinsics.undistortPixelToNormalized(px.x, px.y);
        expect(recoveredNorm.x, closeTo(pCam.x / pCam.z, 5e-7));
        expect(recoveredNorm.y, closeTo(pCam.y / pCam.z, 5e-7));
      }
    });
  });

  group('MultiViewDltTriangulator (SVD/Jacobi DLT + Subset Outlier Rejection)', () {
    List<CalibratedCameraView> buildTestRig() {
      final intr = CameraDistortionIntrinsics.fromHorizontalFov(
        widthPx: 1280,
        heightPx: 720,
        horizontalFovDegrees: 72.0,
        k1: -0.14,
        k2: 0.04,
      );

      CalibratedCameraView makeCam(String id, Vector3 posWorld, double yawRad) {
        // Camera looks along +Z_cam; rotate around Y by yawRad.
        final qCamFromWorld = Quaternion.axisAngle(Vector3(0, 1, 0), -yawRad);
        final r = qCamFromWorld.asRotationMatrix();
        final t = -r.transformed(posWorld);
        return CalibratedCameraView(
          id: id,
          intrinsics: intr,
          worldToCameraRotation: r,
          worldToCameraTranslation: t,
        );
      }

      return <CalibratedCameraView>[
        makeCam('pc_faro', Vector3(0.0, 1.20, 0.0), 0.0),
        makeCam('visor_front', Vector3(-0.45, 1.55, 0.20), -0.32),
        makeCam('joy_front', Vector3(0.48, 1.05, 0.25), 0.35),
        makeCam('aux_side', Vector3(0.85, 1.30, 0.45), 0.55),
      ];
    }

    test('recovers exact 3D world point across distorted multi-camera views', () {
      final cams = buildTestRig();
      final triangulator = MultiViewDltTriangulator(cameras: cams);
      final truth = Vector3(0.12, 1.34, 1.48);

      final obs = <String, Vector2>{
        for (final c in cams) c.id: c.projectWorldToPixel(truth),
      };

      final res = triangulator.triangulatePixels(obs);
      expect(res, isNotNull);
      expect(res!.pointWorld.distanceTo(truth), lessThan(1e-5));
      expect(res.meanNormalizedReprojectionError, lessThan(1e-7));
      expect(res.inlierCameraCount, equals(4));
    });

    test('rejects an occluded camera view with a 220 px outlier spike', () {
      final cams = buildTestRig();
      final triangulator = MultiViewDltTriangulator(
        cameras: cams,
        targetNormalizedReprojectionError: 0.008,
        maxCamerasToDrop: 1,
      );
      final truth = Vector3(-0.08, 1.28, 1.52);

      final obs = <String, Vector2>{
        for (final c in cams) c.id: c.projectWorldToPixel(truth),
      };
      // Corrupt 'joy_front' by +220 px horizontally and -140 px vertically
      obs['joy_front'] = obs['joy_front']! + Vector2(220.0, -140.0);

      final res = triangulator.triangulatePixels(
        obs,
        enableOutlierRejection: true,
      );
      expect(res, isNotNull);
      expect(res!.pointWorld.distanceTo(truth), lessThan(0.002));
      expect(
        res.perCameraWeights['joy_front']!,
        lessThan(res.perCameraWeights['pc_faro']! * 0.15),
      );
    });
  });

  group('KabschHorizonAligner (Planar & 3D Procrustes + Horizon Leveling)', () {
    test('recovers exact rigid transform on a flat z=0 calibration board with det(R)=+1', () {
      final boardPts = <Vector3>[
        Vector3(-0.10, -0.07, 0.0),
        Vector3(0.10, -0.07, 0.0),
        Vector3(0.10, 0.07, 0.0),
        Vector3(-0.10, 0.07, 0.0),
        Vector3(0.03, 0.02, 0.0),
      ];
      final trueRot = Quaternion.euler(0.38, -0.27, 0.21).asRotationMatrix();
      final trueTrans = Vector3(0.18, -0.42, 1.36);
      final worldPts = <Vector3>[
        for (final p in boardPts) trueRot.transformed(p) + trueTrans,
      ];

      final solved = KabschHorizonAligner.alignCorrespondingPoints(
        sourcePoints: boardPts,
        targetPoints: worldPts,
      );
      expect(solved, isNotNull);
      expect(solved!.rmsErrorMeters, lessThan(1e-6));
      expect(solved.rotation.determinant(), closeTo(1.0, 1e-6));
      expect(solved.translation.distanceTo(trueTrans), lessThan(1e-6));
    });

    test('findQuietFrameWindow isolates stationary board segment and computes medians', () {
      final frames = <List<Vector3?>>[];
      // 6 moving frames
      for (var t = 0; t < 6; t++) {
        final shift = t * 0.03;
        frames.add(<Vector3?>[
          Vector3(shift, 0, 1),
          Vector3(0.1 + shift, 0, 1),
          Vector3(0, 0.1 + shift, 1),
          Vector3(0.1 + shift, 0.1 + shift, 1),
        ]);
      }
      // 10 quiet frames (with 1 missing sample)
      for (var t = 0; t < 10; t++) {
        frames.add(<Vector3?>[
          Vector3(0.200, 0.000, 1.200),
          t == 4 ? null : Vector3(0.300, 0.000, 1.200),
          Vector3(0.200, 0.100, 1.200),
          Vector3(0.300, 0.100, 1.200),
        ]);
      }

      final win = KabschHorizonAligner.findQuietFrameWindow(
        frames,
        minWindowFrames: 8,
      );
      expect(win, equals((6, 16)));

      final med = KabschHorizonAligner.medianPointsInWindow(frames, win!.$1, win.$2);
      expect(med.length, 4);
      expect(med[1]!.distanceTo(Vector3(0.300, 0.000, 1.200)), lessThan(1e-6));
    });

    test('levelCameraPointToHorizon removes laptop webcam upward pitch bias', () {
      // Laptop camera at height 1.18 m pitched UP by +15 degrees looking at a
      // visor at true world height 1.61 m (dy = +0.43 m above camera) and
      // horizontal distance z_horiz = 1.40 m.
      const pitch = 15.0 * math.pi / 180.0;
      const dyTrue = 0.43;
      const zHorizTrue = 1.40;
      // Project into tilted CV camera coordinates (+Y down, +Z optical axis):
      final yUpCam = dyTrue * math.cos(pitch) - zHorizTrue * math.sin(pitch);
      final zCam = dyTrue * math.sin(pitch) + zHorizTrue * math.cos(pitch);
      final pCv = Vector3(-0.15, -yUpCam, zCam);

      final leveled = KabschHorizonAligner.levelCameraPointToHorizon(
        pCv,
        pitchRadians: pitch,
      );
      expect(leveled.x, closeTo(0.15, 1e-6));
      expect(leveled.y, closeTo(dyTrue, 1e-6));
      expect(leveled.z, closeTo(zHorizTrue, 1e-6));
    });
  });

  group('CausalLandmarkStabilizer3D & ForwardKinematicChainRigidifier', () {
    test('spike gate blocks teleportation glitch and marks extrapolated frames non-measured', () {
      final stab = CausalLandmarkStabilizer3D(
        maxSpeedMetersPerSec: 6.0,
        maxConsecutiveRejections: 4,
        maxExtrapolationFrames: 3,
      );

      final s0 = stab.updateObserved(Vector3(0.20, -0.15, -0.55), 0.016);
      expect(s0.isMeasuredObservation, isTrue);

      // Single-frame 2.4 m background glitch over 16 ms (150 m/s) -> rejected!
      final glitch = stab.updateObserved(Vector3(2.60, 0.80, -0.55), 0.016);
      expect(glitch.isHeldBySpikeGate, isTrue);
      expect(glitch.isMeasuredObservation, isFalse);
      expect(glitch.position.x, closeTo(0.20, 1e-6));

      // Missing observations extrapolate for 3 frames with isMeasuredObservation == false
      final p1 = stab.updateMissing(0.016);
      final p2 = stab.updateMissing(0.016);
      final p3 = stab.updateMissing(0.016);
      final p4 = stab.updateMissing(0.016);
      expect(p1, isNotNull);
      expect(p1!.isPredicted, isTrue);
      expect(p1.isMeasuredObservation, isFalse);
      expect(p2, isNotNull);
      expect(p3, isNotNull);
      expect(p4, isNull);
    });

    test('RollingMedianBoneEstimator ignores outlier frame and ForwardKinematicChainRigidifier holds exact lengths', () {
      final estimator = RollingMedianBoneEstimator(
        seedLengthsMeters: VrAnthropometricSegmentRatios.buildUpperBodySeeds(1.75),
        windowSeconds: 5.0,
      );
      final rigidifier = ForwardKinematicChainRigidifier(
        jointHierarchy: const <String, List<String>>{
          'right_shoulder': <String>['right_elbow'],
          'right_elbow': <String>['right_wrist'],
        },
      );

      // Feed 8 clean frames with true upper arm = 0.31 m, forearm = 0.25 m, plus 1 wild outlier
      for (var i = 0; i < 9; i++) {
        final isOutlier = i == 4;
        estimator.recordMeasuredFrame(
          <String, Vector3>{
            'right_shoulder': Vector3(0.20, 1.42, 0.0),
            'right_elbow': Vector3(0.20, 1.42 - (isOutlier ? 0.95 : 0.31), 0.0),
            'right_wrist': Vector3(
              0.20,
              1.42 - (isOutlier ? 0.95 : 0.31),
              -(isOutlier ? 1.20 : 0.25),
            ),
          },
          timeSeconds: i * 0.05,
        );
      }

      expect(
        estimator.lengthFor('right_shoulder->right_elbow'),
        closeTo(0.31, 1e-6),
      );
      expect(
        estimator.lengthFor('right_elbow->right_wrist'),
        closeTo(0.25, 1e-6),
      );

      // Foreshortened noisy input preserves unit directions while enforcing exact 0.31 m & 0.25 m
      final corrected = rigidifier.rigidify(
        <String, Vector3>{
          'right_shoulder': Vector3(0.20, 1.42, 0.0),
          'right_elbow': Vector3(0.20, 1.27, -0.15),
          'right_wrist': Vector3(0.26, 1.27, -0.34),
        },
        estimator.currentLengths,
      );

      expect(
        corrected['right_shoulder']!.distanceTo(corrected['right_elbow']!),
        closeTo(0.31, 1e-6),
      );
      expect(
        corrected['right_elbow']!.distanceTo(corrected['right_wrist']!),
        closeTo(0.25, 1e-6),
      );
    });
  });
}
