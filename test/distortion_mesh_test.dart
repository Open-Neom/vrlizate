import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('DistortionMesh', () {
    test('cardboard V1 preset creates mesh without error', () {
      final mesh = DistortionMesh.cardboardV1();
      expect(mesh.coefficients, equals([0.441, 0.156]));
      expect(mesh.resolution, equals(40));
    });

    test('no distortion produces identity mapping', () {
      final mesh = DistortionMesh.none();
      // Center point (0,0) should map to itself
      final distorted = mesh.distort(0, 0);
      expect(distorted.dx, closeTo(0, 1e-6));
      expect(distorted.dy, closeTo(0, 1e-6));
    });

    test('barrel distortion expands outward', () {
      final mesh = DistortionMesh.cardboardV1();
      // A point at normalized (0.5, 0) should be pushed further out
      final distorted = mesh.distort(0.5, 0);
      expect(distorted.dx.abs(), greaterThan(0.5));
    });

    test('distortion is symmetric around center', () {
      final mesh = DistortionMesh.cardboardV2();
      final left = mesh.distort(-0.5, 0);
      final right = mesh.distort(0.5, 0);
      expect(left.dx, closeTo(-right.dx, 1e-6));
    });

    test('inverse distortion converges', () {
      final mesh = DistortionMesh.cardboardV1();
      // Distort a radius, then inverse distort it
      final r = 0.5;
      final distorted = r * mesh.distortionFactor(r * r);
      final inverse = mesh.inverseDistort(distorted);

      expect(inverse, closeTo(r, 0.01));
    });

    test('mesh grid has correct point count', () {
      final mesh = DistortionMesh(resolution: 10);
      // (10+1) * (10+1) = 121 points
      expect(mesh.originalPoints.length, equals(121));
      expect(mesh.distortedPoints.length, equals(121));
    });

    test('high resolution mesh does not crash', () {
      // Should handle 100x100 grid (10201 points)
      expect(() => DistortionMesh(resolution: 100), returnsNormally);
    });
  });

  group('LensDistortion', () {
    test('no distortion returns identity', () {
      const ld = LensDistortion.none;
      final result = ld.distort(0.5, 0.3);
      expect(result.dx, closeTo(0.5, 1e-6));
      expect(result.dy, closeTo(0.3, 1e-6));
    });

    test('cardboard preset distorts outward', () {
      const ld = LensDistortion.cardboard;
      final result = ld.distort(0.5, 0);
      expect(result.dx.abs(), greaterThan(0.5));
    });

    test('distortScreen maps center to center', () {
      const ld = LensDistortion.cardboard;
      final result = ld.distortScreen(200, 150, 400, 300);
      // Center (200,150) in 400x300 → normalized (0,0) → no distortion at center
      expect(result.dx, closeTo(200, 1));
      expect(result.dy, closeTo(150, 1));
    });
  });

  group('DeviceParams', () {
    test('all presets have valid distortion coefficients', () {
      final presets = [
        DeviceParams.cardboardV1,
        DeviceParams.cardboardV2,
        DeviceParams.gearVr,
        DeviceParams.generic,
        DeviceParams.none,
      ];

      for (final p in presets) {
        expect(p.distortionCoefficients.length, greaterThanOrEqualTo(2));
        expect(p.interLensDistance, greaterThan(0));
        expect(p.fovAngles.length, equals(4));
      }
    });

    test('ipd alias returns interLensDistance', () {
      expect(DeviceParams.cardboardV2.ipd, equals(DeviceParams.cardboardV2.interLensDistance));
    });
  });
}
