import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('Scene fog controls', () {
    test('default to uniform, fully opaque, uncut fog', () {
      final scene = Scene();
      expect(scene.fogMaxOpacity, 1.0);
      expect(scene.fogCutoffDistance, 0);
      expect(scene.fogHeightFalloff, 0);
    });

    test('accept open-world settings', () {
      final scene = Scene(
        fogDensity: 0.01,
        fogMaxOpacity: 0.75,
        fogCutoffDistance: 320,
        fogHeightFalloff: 0.05,
      );
      expect(scene.fogMaxOpacity, 0.75);
      expect(scene.fogCutoffDistance, 320);
      expect(scene.fogHeightFalloff, 0.05);
    });

    test('reject out-of-range values', () {
      expect(() => Scene(fogMaxOpacity: 1.5), throwsA(isA<AssertionError>()));
      expect(
        () => Scene(fogCutoffDistance: -1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Scene(fogHeightFalloff: -0.1),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
