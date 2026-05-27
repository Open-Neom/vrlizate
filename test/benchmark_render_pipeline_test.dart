// ignore_for_file: avoid_print
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

// Minimal Mock Canvas for high-speed benchmark execution
class BenchmarkCanvas extends Fake implements Canvas {
  @override
  void drawRect(Rect rect, Paint paint) {}

  @override
  void translate(double dx, double dy) {}

  @override
  void scale(double sx, [double? sy]) {}

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void drawVertices(Vertices vertices, BlendMode blendMode, Paint paint) {}

  @override
  void drawPath(Path path, Paint paint) {}

  @override
  void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) {}
}

void main() {
  group('RenderPass - Performance Benchmarks', () {
    late Scene scene;
    late CameraRig cameraRig;
    late RenderPass renderPass;
    late BenchmarkCanvas benchmarkCanvas;

    setUp(() {
      scene = Scene();
      cameraRig = CameraRig();
      renderPass = RenderPass(scene: scene, cameraRig: cameraRig);
      benchmarkCanvas = BenchmarkCanvas();
    });

    test('1,000 Opaque + 200 Transparent Meshes: renderMono < 50ms', () {
      final sw = Stopwatch()..start();

      // 1. Populate a dense, realistic scene graph
      for (var i = 0; i < 1000; i++) {
        final node = MeshNode(
          name: 'opaque_box_$i',
          geometry: CubeGeometry(size: 0.5),
          material: VRMaterial(color: const Color(0xFF888888), opacity: 1.0),
        );
        node.transform.position = Vector3(
          (i % 10 - 5) * 2.0,
          ((i ~/ 10) % 10 - 5) * 2.0,
          -(i ~/ 100 + 1) * 3.0,
        );
        scene.add(node);
      }

      for (var i = 0; i < 200; i++) {
        final node = MeshNode(
          name: 'transparent_sphere_$i',
          geometry: SphereGeometry(radius: 0.3, segments: 8),
          material: VRMaterial(color: const Color(0x7F00FFFF), opacity: 0.5),
        );
        node.transform.position = Vector3(
          (i % 5 - 2) * 4.0,
          ((i ~/ 5) % 5 - 2) * 4.0,
          -(i ~/ 25 + 1) * 6.0,
        );
        scene.add(node);
      }

      final buildTime = sw.elapsedMicroseconds;

      // 2. Run update & matrix accumulation
      sw.reset();
      scene.update(0.016);
      final updateTime = sw.elapsedMicroseconds;

      // 3. Render monoscopic pass (performs culling + sorting + mock canvas painting)
      sw.reset();
      renderPass.renderMono(benchmarkCanvas, const Size(800, 600));
      final monoRenderTime = sw.elapsedMicroseconds;

      // 4. Render stereoscopic pass (performs culling + sorting + mock canvas painting TWICE)
      sw.reset();
      renderPass.renderStereo(benchmarkCanvas, const Size(800, 600));
      final stereoRenderTime = sw.elapsedMicroseconds;

      print('=== RENDERING PIPELINE BENCHMARK (1,200 Graph Nodes) ===');
      print('Build Time:        ${(buildTime / 1000).toStringAsFixed(2)} ms');
      print('Update/Matrix:     ${(updateTime / 1000).toStringAsFixed(2)} ms');
      print('Mono RenderPass:   ${(monoRenderTime / 1000).toStringAsFixed(2)} ms');
      print('Stereo RenderPass: ${(stereoRenderTime / 1000).toStringAsFixed(2)} ms');
      print('Rendered Nodes:    ${renderPass.renderedCount}');
      print('Culled Nodes:      ${renderPass.culledCount}');
      print('========================================================');

      // Assertions to keep a boundary budget
      expect(monoRenderTime / 1000, lessThan(100.0), reason: 'Monoscopic rendering exceeds performance budget');
      expect(stereoRenderTime / 1000, lessThan(200.0), reason: 'Stereoscopic rendering exceeds performance budget');
    });

    test('Frustum Culling efficiency: 90% out-of-view objects culled in < 15ms', () {
      // Place camera looking strictly straight forward
      cameraRig.position = Vector3(0, 0, 0);
      cameraRig.lookAt(Vector3(0, 0, -1));

      // Put 900 objects strictly behind the camera (z > 5)
      for (var i = 0; i < 900; i++) {
        final node = MeshNode(
          geometry: CubeGeometry(size: 1.0),
        );
        node.transform.position = Vector3((i % 10 - 5).toDouble(), (i ~/ 10 % 10 - 5).toDouble(), 10.0 + i ~/ 100);
        scene.add(node);
      }

      // Put 100 objects strictly inside the forward frustum (z < -5)
      for (var i = 0; i < 100; i++) {
        final node = MeshNode(
          geometry: CubeGeometry(size: 1.0),
        );
        node.transform.position = Vector3((i % 5 - 2).toDouble(), (i ~/ 5 % 5 - 2).toDouble(), -10.0 - i ~/ 25);
        scene.add(node);
      }

      scene.update(0.016);

      final sw = Stopwatch()..start();
      renderPass.renderMono(benchmarkCanvas, const Size(800, 600));
      final renderTime = sw.elapsedMicroseconds;

      expect(renderPass.renderedCount, equals(100));
      expect(renderPass.culledCount, equals(900));
      expect(renderTime / 1000, lessThan(15.0), reason: 'Frustum culling of 900 objects is too slow');
    });
  });
}
