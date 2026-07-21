import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('HologramMeshNode', () {
    test('initializes with custom parameters', () {
      final node = HologramMeshNode(
        name: 'test_hologram',
        geometry: SphereGeometry(radius: 1.0),
        hologramColor: const Color(0xFF00FF00),
        flickerSpeed: 8.0,
      );

      expect(node.name, equals('test_hologram'));
      expect(node.flickerSpeed, equals(8.0));
      expect(node.material.color, equals(const Color(0xFF00FF00)));
    });

    test('updates global time tick successfully', () {
      HologramMeshNode.time = 4.2;
      expect(HologramMeshNode.time, equals(4.2));
    });
  });

  group('WifiSensingSystem', () {
    test('initializes as inactive', () {
      final sensing = WifiSensingSystem();
      expect(sensing.isActive, isFalse);
      expect(sensing.trackedSubjects, isEmpty);
      sensing.dispose();
    });

    test('simulated CSI frame structures are correct', () {
      final frame = CsiFrame(
        timestamp: 1000,
        amplitudes: [1.0, 1.2, 0.9, 1.1],
      );

      expect(frame.timestamp, equals(1000));
      expect(frame.amplitudes.length, equals(4));
    });
  });

  group('WifiRadarNode', () {
    test('initializes and configures correctly', () {
      final node = WifiRadarNode(
        name: 'test_radar',
        pulseSpeed: 6.0,
        radarColor: const Color(0xFFFF00FF),
      );

      expect(node.name, equals('test_radar'));
      expect(node.pulseSpeed, equals(6.0));
      expect(node.radarColor, equals(const Color(0xFFFF00FF)));
    });
  });

  group('MediaPipeHandDriver', () {
    test('converts 21 MediaPipe landmarks to OpenXR HandState joints', () {
      final state = HandState(hand: ControllerHand.right);
      final landmarks = List.generate(21, (i) => Vector3(i * 0.01, i * 0.02, i * 0.03));

      MediaPipeHandDriver.updateHandFromLandmarks(state, landmarks);

      expect(state.tracked, isTrue);
      expect(state.joint(HandJoint.wrist), equals(landmarks[0]));
      expect(state.joint(HandJoint.thumbTip), equals(landmarks[4]));
      expect(state.joint(HandJoint.indexTip), equals(landmarks[8]));
      expect(state.palmPosition, equals((landmarks[0] + landmarks[9]) * 0.5));
    });
  });

  group('DeviceParams QR Parser', () {
    test('decodes Cardboard QR parameters from URI', () {
      final uri = Uri.parse('http://google.com/cardboard/cfg?v=OpenNeom&m=VR-One&ipd=0.065&std=0.040&k1=0.32&k2=0.50');
      final params = DeviceParams.fromCardboardQrUri(uri);

      expect(params.vendor, equals('OpenNeom'));
      expect(params.model, equals('VR-One'));
      expect(params.interLensDistance, equals(0.065));
      expect(params.screenToLensDistance, equals(0.040));
      expect(params.distortionCoefficients, equals([0.32, 0.50]));
    });

    test('decodes official Google Cardboard Protobuf payload from ?p= parameter', () {
      // Synthesize a valid Base64 Protobuf payload with field 1="Google" (vendor) and field 2="Cardboard" (model)
      final protobufUri = Uri.parse('http://google.com/cardboard/cfg?p=CgZHb29nbGUSBENhcmQ');
      final params = DeviceParams.fromCardboardQrUri(protobufUri);

      expect(params.vendor, contains('Google'));
      expect(params.model, contains('Card'));
    });
  });

  group('FaceTrackerDriver', () {
    test('updates face offset and calculates projection matrix', () {
      final rig = CameraRig();
      final driver = FaceTrackerDriver(cameraRig: rig);

      driver.updateFacePosition(0.05, -0.02, 0.45);
      expect(driver.facePosition, equals(Vector3(0.05, -0.02, 0.45)));

      final proj = driver.projectionMatrix;
      expect(proj.storage.any((v) => v.isNaN), isFalse);
    });
  });

  group('UV Texture & PBR Material', () {
    test('VRMaterial accepts texture map and PBR roughness/metallic values', () {
      final texture = VRTexture(name: 'albedo');
      final mat = VRMaterial(
        color: const Color(0xFF00FF00),
        metallic: 0.8,
        roughness: 0.2,
        map: texture,
      );

      expect(mat.metallic, equals(0.8));
      expect(mat.roughness, equals(0.2));
      expect(mat.map, equals(texture));
    });
  });

  group('VRAnaglyphPainter', () {
    test('initializes with renderer and camera', () {
      final camera = VRCamera();
      final projection = StereoscopicProjection();
      final painter = VRAnaglyphPainter(
        renderer: _StubRenderer(),
        camera: camera,
        projection: projection,
      );

      expect(painter.shouldRepaint(painter), isTrue);
    });
  });
}

class _StubRenderer implements VRRenderer {
  @override
  void renderEye(Canvas canvas, Size viewportSize, VRCamera camera, StereoscopicProjection projection, bool isLeftEye) {}
}
