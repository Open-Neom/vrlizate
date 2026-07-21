import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';
// ignore: avoid_relative_lib_imports
import '../example/lib/demos.dart';

void main() {
  group('VRlizate Example Demos', () {
    late VREngine engine;

    setUp(() {
      engine = VREngine();
    });

    tearDown(() {
      engine.dispose();
    });

    test('GridDemo initializes and disposes correctly', () {
      final demo = GridDemo(engine);
      expect(demo.nodes, isEmpty);
      demo.init();
      expect(demo.nodes, isNotEmpty);
      demo.update(0.016);
      demo.dispose();
      expect(demo.nodes, isEmpty);
    });

    test('PhysicsPlaygroundDemo initializes and disposes correctly', () {
      final demo = PhysicsPlaygroundDemo(engine);
      expect(demo.nodes, isEmpty);
      demo.init();
      expect(demo.nodes, isNotEmpty);
      demo.update(0.016);
      demo.dispose();
      expect(demo.nodes, isEmpty);
    });

    test('SpaceFlightDemo initializes and disposes correctly', () {
      final demo = SpaceFlightDemo(engine);
      expect(demo.nodes, isEmpty);
      demo.init();
      expect(demo.nodes, isNotEmpty);
      demo.update(0.016);
      demo.dispose();
      expect(demo.nodes, isEmpty);
    });

    test('VRCinemaDemo initializes and disposes correctly', () {
      final demo = VRCinemaDemo(engine);
      expect(demo.nodes, isEmpty);
      demo.init();
      expect(demo.nodes, isNotEmpty);
      demo.update(0.016);
      demo.dispose();
      expect(demo.nodes, isEmpty);
    });

    test('WifiRadarDemo initializes and disposes correctly', () {
      final demo = WifiRadarDemo(engine);
      expect(demo.nodes, isEmpty);
      demo.init();
      expect(demo.nodes, isNotEmpty);
      demo.update(0.016);
      demo.dispose();
      expect(demo.nodes, isEmpty);
    });

    test('DepthDisplacedGeometry generates displaced vertices correctly', () {
      final depthMap = [0.0, 0.5, 1.0, 0.2];
      final geometry = DepthDisplacedGeometry(
        widthSegments: 1,
        heightSegments: 1,
        width: 2.0,
        height: 2.0,
        depthMap: depthMap,
        maxDisplacement: 2.0,
      );

      // Grid of 1x1 segments has 4 vertices: (0,0), (1,0), (0,1), (1,1)
      expect(geometry.vertices.length, equals(4));
      // First vertex depth (index 0) displacement: 0.0 * 2.0 = 0.0
      expect(geometry.vertices[0].z, closeTo(0.0, 1e-5));
      // Third vertex depth (index 2) displacement: 1.0 * 2.0 = 2.0
      expect(geometry.vertices[2].z, closeTo(2.0, 1e-5));
      // Indices for a 1x1 quad should be 6 (2 triangles)
      expect(geometry.indices.length, equals(6));
    });

    test('CameraRig faceTrackedProjectionMatrix calculates generalized perspective', () {
      final rig = CameraRig(near: 0.1, far: 100.0);
      final eyePos = Vector3(0.02, -0.01, 0.5); // user's eye relative to screen center

      final matrix = rig.faceTrackedProjectionMatrix(
        eyePosRelative: eyePos,
        screenWidth: 0.16,
        screenHeight: 0.08,
      );

      // Verify that matrix has values (non-identity and non-zero)
      expect(matrix.storage[0], isNot(equals(1.0)));
      expect(matrix.storage[15], equals(0.0)); // perspective projection matrices have storage[15] = 0
    });
  });
}
