import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:vrlizate/vrlizate.dart';

/// Material system tests — validates VRMaterial and PBR material properties.
void main() {
  group('Material — Correctness', () {
    test('VRMaterial toPaint returns valid Paint', () {
      final mat = VRMaterial(
        color: const Color(0xFFFF0000),
        opacity: 0.8,
        metallic: 0.5,
        roughness: 0.3,
      );

      final paint = mat.toPaint(lightFactor: 0.7);
      expect(paint.color.a, greaterThan(0));
    });

    test('wireframe material produces stroke paint', () {
      final mat = VRMaterial(color: const Color(0xFF00FF00), wireframe: true);

      final paint = mat.toPaint(lightFactor: 1.0);
      expect(paint.style, equals(PaintingStyle.stroke));
    });

    test('PBR material stores metallic and roughness', () {
      final pbr = PBRMaterial(
        color: const Color(0xFFCCCCCC),
        metallic: 0.9,
        roughness: 0.1,
      );

      expect(pbr.metallic, closeTo(0.9, 1e-3));
      expect(pbr.roughness, closeTo(0.1, 1e-3));
    });

    test('emissive material property is preserved', () {
      final mat = VRMaterial(
        color: const Color(0xFF000000),
        emissive: const Color(0xFFFF0000),
      );

      expect(mat.emissive, equals(const Color(0xFFFF0000)));
    });

    test('double-sided flag is preserved', () {
      final mat = VRMaterial(color: const Color(0xFFFFFFFF), doubleSided: true);
      expect(mat.doubleSided, isTrue);

      final mat2 = VRMaterial(color: const Color(0xFFFFFFFF));
      expect(mat2.doubleSided, isFalse);
    });

    test('opacity affects paint alpha', () {
      final opaque = VRMaterial(color: const Color(0xFFFF0000), opacity: 1.0);
      final transparent = VRMaterial(
        color: const Color(0xFFFF0000),
        opacity: 0.5,
      );

      final opaquePaint = opaque.toPaint(lightFactor: 1.0);
      final transPaint = transparent.toPaint(lightFactor: 1.0);

      expect(opaquePaint.color.a, greaterThan(transPaint.color.a));
    });
  });

  group('Material — Stress', () {
    test('10,000 toPaint calls < 50ms', () {
      final mat = VRMaterial(
        color: const Color(0xFF808080),
        metallic: 0.5,
        roughness: 0.5,
      );

      final sw = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        mat.toPaint(lightFactor: i / 10000);
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });
}
