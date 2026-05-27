import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

// A mock Canvas to capture draw calls made by RenderPass and meshes
class MockCanvas extends Fake implements Canvas {
  final List<String> operations = [];

  @override
  void drawRect(Rect rect, Paint paint) {
    operations.add('drawRect: $rect, color=${paint.color.toARGB32().toRadixString(16)}');
  }

  @override
  void translate(double dx, double dy) {
    operations.add('translate: $dx, $dy');
  }

  @override
  void scale(double sx, [double? sy]) {
    operations.add('scale: $sx, $sy');
  }

  @override
  void save() {
    operations.add('save');
  }

  @override
  void restore() {
    operations.add('restore');
  }

  @override
  void drawVertices(Vertices vertices, BlendMode blendMode, Paint paint) {
    operations.add('drawVertices: mode=${vertices.hashCode}, blendMode=$blendMode, paintColor=${paint.color.toARGB32().toRadixString(16)}');
  }

  @override
  void drawPath(Path path, Paint paint) {
    operations.add('drawPath');
  }

  @override
  void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) {
    operations.add('clipRect: $rect');
  }
}

void main() {
  group('RenderPass - Pipeline Regression', () {
    late Scene scene;
    late CameraRig cameraRig;
    late RenderPass renderPass;
    late MockCanvas mockCanvas;

    setUp(() {
      scene = Scene();
      cameraRig = CameraRig();
      renderPass = RenderPass(scene: scene, cameraRig: cameraRig);
      mockCanvas = MockCanvas();
    });

    test('renders background and sets up transforms', () {
      const size = Size(800, 600);
      renderPass.renderMono(mockCanvas, size);

      // Verify that background was drawn and transforms were pushed
      expect(mockCanvas.operations, contains(
        'drawRect: Rect.fromLTRB(0.0, 0.0, 800.0, 600.0), color=ff0a0a1a',
      ));
      expect(mockCanvas.operations, contains('save'));
      expect(mockCanvas.operations, contains('translate: 400.0, 300.0'));
      expect(mockCanvas.operations, contains('scale: 400.0, -300.0'));
      expect(mockCanvas.operations, contains('restore'));
    });

    test('opaque and transparent nodes are separated and rendered', () {
      // 1. Setup a simple scene with 1 opaque and 1 transparent node
      final opaqueMesh = MeshNode(
        name: 'opaque_box',
        geometry: CubeGeometry(size: 1.0),
        material: VRMaterial(color: const Color(0xFFFF0000), opacity: 1.0),
      );
      opaqueMesh.transform.position = Vector3(0, 0, -5); // In front of camera

      final transparentMesh = MeshNode(
        name: 'transparent_box',
        geometry: CubeGeometry(size: 1.0),
        material: VRMaterial(color: const Color(0xFF00FF00), opacity: 0.5),
      );
      transparentMesh.transform.position = Vector3(0, 0, -3); // Closer to camera

      scene.add(opaqueMesh);
      scene.add(transparentMesh);

      // Force matrix propagation
      scene.update(0.01);

      // 2. Render monoscopic
      renderPass.renderMono(mockCanvas, const Size(800, 600));

      // Verify node counts in RenderPass
      expect(renderPass.renderedCount, equals(2));
      expect(renderPass.culledCount, equals(0));

      // Check order: opaque is rendered first, then transparent.
      // Filter out drawVertices operations.
      final draws = mockCanvas.operations
          .where((op) => op.contains('drawVertices'))
          .toList();

      expect(draws.length, equals(2));
      // Red (opaque) should be rendered first
      expect(draws[0], contains('paintColor=ffff0000'));
      // Green (transparent) should be rendered second
      expect(draws[1], contains('paintColor=7f00ff00'));
    });

    test('transparent nodes are sorted back-to-front', () {
      // Setup camera at zero
      cameraRig.position = Vector3(0, 0, 0);

      // Add three transparent nodes at different depths (z = -10, -5, -2)
      final farMesh = MeshNode(
        name: 'far_transparent',
        geometry: CubeGeometry(size: 1.0),
        material: VRMaterial(color: const Color(0xFF0000FF), opacity: 0.5), // Blue
      );
      farMesh.transform.position = Vector3(0, 0, -10);

      final midMesh = MeshNode(
        name: 'mid_transparent',
        geometry: CubeGeometry(size: 1.0),
        material: VRMaterial(color: const Color(0xFF00FF00), opacity: 0.5), // Green
      );
      midMesh.transform.position = Vector3(0, 0, -5);

      final nearMesh = MeshNode(
        name: 'near_transparent',
        geometry: CubeGeometry(size: 1.0),
        material: VRMaterial(color: const Color(0xFFFF0000), opacity: 0.5), // Red
      );
      nearMesh.transform.position = Vector3(0, 0, -2);

      scene.add(farMesh);
      scene.add(midMesh);
      scene.add(nearMesh);

      scene.update(0.01);

      renderPass.renderMono(mockCanvas, const Size(800, 600));

      final draws = mockCanvas.operations
          .where((op) => op.contains('drawVertices'))
          .toList();

      expect(draws.length, equals(3));
      // Must be rendered back-to-front (far to near)
      // 1. Blue (depth = -10)
      expect(draws[0], contains('paintColor=7f0000ff'));
      // 2. Green (depth = -5)
      expect(draws[1], contains('paintColor=7f00ff00'));
      // 3. Red (depth = -2)
      expect(draws[2], contains('paintColor=7fff0000'));
    });

    test('nodes outside frustum are correctly culled', () {
      cameraRig.position = Vector3(0, 0, 0);
      cameraRig.lookAt(Vector3(0, 0, -1)); // look straight forward

      // Node in front of camera (should render)
      final insideMesh = MeshNode(
        name: 'inside',
        geometry: CubeGeometry(size: 1.0),
      );
      insideMesh.transform.position = Vector3(0, 0, -5);

      // Node behind camera (should be culled)
      final outsideMesh = MeshNode(
        name: 'outside',
        geometry: CubeGeometry(size: 1.0),
      );
      outsideMesh.transform.position = Vector3(0, 0, 5);

      scene.add(insideMesh);
      scene.add(outsideMesh);

      scene.update(0.01);

      renderPass.renderMono(mockCanvas, const Size(800, 600));

      // Culled counts
      expect(renderPass.renderedCount, equals(1));
      expect(renderPass.culledCount, equals(1));
    });

    test('stereo rendering draws to left and right viewports with divider', () {
      const size = Size(800, 600);
      renderPass.renderStereo(mockCanvas, size);

      // Should clip left side, render, clip right side, render, draw black divider line
      expect(mockCanvas.operations, contains('clipRect: Rect.fromLTRB(0.0, 0.0, 400.0, 600.0)'));
      expect(mockCanvas.operations, contains('clipRect: Rect.fromLTRB(400.0, 0.0, 800.0, 600.0)'));
      expect(mockCanvas.operations, contains('translate: 400.0, 0.0'));
      expect(mockCanvas.operations, contains('drawRect: Rect.fromLTRB(398.0, 0.0, 402.0, 600.0), color=ff000000'));
    });

    test('lens barrel distortion mathematically warps vertex projections', () {
      // 1. Setup a simple scene with a single forward mesh
      final testMesh = MeshNode(
        geometry: CubeGeometry(size: 1.0),
        material: VRMaterial(color: const Color(0xFF00FF00)),
      );
      testMesh.transform.position = Vector3(1, 1, -5); // Offset from center to ensure radial warping
      scene.add(testMesh);
      scene.update(0.01);

      // 2. Standard rendering (distortion disabled)
      expect(MeshNode.activeDistortionCoefficients, isNull);
      renderPass.enableLensDistortion = false;
      renderPass.renderMono(mockCanvas, const Size(800, 600));

      expect(MeshNode.activeDistortionCoefficients, isNull);
      expect(renderPass.renderedCount, equals(1));

      final drawsNormal = mockCanvas.operations
          .where((op) => op.contains('drawVertices'))
          .toList();
      expect(drawsNormal.length, equals(1));

      // 3. Enable radial barrel distortion
      mockCanvas.operations.clear();
      renderPass.enableLensDistortion = true;
      renderPass.distortionCoefficients = const [0.44, 0.15]; // cardboard coefficients
      renderPass.renderMono(mockCanvas, const Size(800, 600));

      // Global static field should be automatically cleared inside try-finally block!
      expect(MeshNode.activeDistortionCoefficients, isNull);

      final drawsDistorted = mockCanvas.operations
          .where((op) => op.contains('drawVertices'))
          .toList();
      expect(drawsDistorted.length, equals(1));

      // The drawn vertices object must be different (and not null) due to different warped coordinates!
      expect(drawsDistorted.first, isNot(equals(drawsNormal.first)));
    });
  });
}
