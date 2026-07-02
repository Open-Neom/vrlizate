import 'dart:ui';

import 'package:vector_math/vector_math.dart';

import '../../effects/distortion_mesh.dart';
import '../../scene/mesh.dart';
import '../../scene/node.dart';
import '../../scene/scene.dart';
import '../../utils/frustum.dart';
import '../camera/camera_rig.dart';

/// Render pass that traverses the scene and renders to a canvas.
/// Handles: frustum culling, depth sorting, lighting injection, background.
class RenderPass {
  final Scene scene;
  final CameraRig cameraRig;

  int _culledCount = 0;
  int _renderedCount = 0;

  /// Whether to apply radial lens distortion correction.
  bool enableLensDistortion = false;

  /// Coefficients for the radial distortion (default is Cardboard V1 [0.441, 0.156])
  List<double> distortionCoefficients = const [0.441, 0.156];

  /// FSR (FidelityFX Super Resolution) simulation: scaling ratio of offline viewport
  double fsrScale = 1.0;

  /// Whether to apply RGB color splitting dispersion correction in distortion
  bool enableChromaticAberration = false;

  /// Transformation matrices for Asynchronous Time Warp (ATW)
  Matrix4? leftAtwMatrix;
  Matrix4? rightAtwMatrix;

  Image? _lastLeftImage;
  Image? _lastRightImage;

  /// Trigger to skip rendering and warp last frame's cached images directly
  bool useATWFallback = false;

  late final DistortionMesh _leftDistortionMesh = DistortionMesh.cardboardV2();
  late final DistortionMesh _rightDistortionMesh = DistortionMesh.cardboardV2();

  RenderPass({required this.scene, required this.cameraRig});

  void dispose() {
    _lastLeftImage?.dispose();
    _lastLeftImage = null;
    _lastRightImage?.dispose();
    _lastRightImage = null;
  }

  int get culledCount => _culledCount;
  int get renderedCount => _renderedCount;

  /// Renders the scene for one eye.
  void render(
    Canvas canvas,
    Size viewportSize, {
    required Matrix4 viewProjection,
  }) {
    _culledCount = 0;
    _renderedCount = 0;

    // Set active distortion coefficients globally for this render pass
    MeshNode.activeDistortionCoefficients = enableLensDistortion ? distortionCoefficients : null;

    try {
      final frustum = VrFrustum.fromViewProjection(viewProjection);
      final lights = scene.lights;

      // Background
      canvas.drawRect(
        Offset.zero & viewportSize,
        Paint()..color = scene.backgroundColor,
      );

      // Setup canvas transform: NDC [-1,1] → screen pixels
      canvas.save();
      canvas.translate(viewportSize.width / 2, viewportSize.height / 2);
      canvas.scale(viewportSize.width / 2, -viewportSize.height / 2);

      // Collect renderable nodes
      final opaqueNodes = <Node>[];
      final transparentNodes = <Node>[];

      scene.root.traverse((node) {
        if (!node.visible) return;
        if (node is! MeshNode) return;

        // Frustum culling
        final cull = frustum.testAabb(node.worldAabb);
        if (cull == CullResult.outside) {
          _culledCount++;
          return;
        }

        // Inject lights for lit meshes
        if (node is LitMeshNode) {
          node.lights.clear();
          node.lights.addAll(lights);
        }

        if (node.material.isTransparent) {
          transparentNodes.add(node);
        } else {
          opaqueNodes.add(node);
        }
      });

      // Render opaque first (front to back for early-z)
      opaqueNodes.sort((a, b) {
        final da = (a.worldPosition - cameraRig.position).length2;
        final db = (b.worldPosition - cameraRig.position).length2;
        return da.compareTo(db);
      });
      for (final node in opaqueNodes) {
        node.onRender(canvas, viewProjection);
        _renderedCount++;
      }

      // Render transparent (back to front)
      transparentNodes.sort((a, b) {
        final da = (a.worldPosition - cameraRig.position).length2;
        final db = (b.worldPosition - cameraRig.position).length2;
        return db.compareTo(da);
      });
      for (final node in transparentNodes) {
        node.onRender(canvas, viewProjection);
        _renderedCount++;
      }

      canvas.restore();

      // Fog overlay
      if (scene.fogDensity > 0) {
        canvas.drawRect(
          Offset.zero & viewportSize,
          Paint()
            ..color = scene.fogColor.withValues(
              alpha: scene.fogDensity.clamp(0, 0.8),
            ),
        );
      }
    } finally {
      // Clear global coefficients to avoid polluting other rendering passes
      MeshNode.activeDistortionCoefficients = null;
    }
  }

  Image _renderEyeToImage(Size viewportSize, Matrix4 viewProjection) {
    final recorder = PictureRecorder();
    final offlineCanvas = Canvas(recorder);

    final double fsrW = (viewportSize.width * fsrScale).roundToDouble();
    final double fsrH = (viewportSize.height * fsrScale).roundToDouble();
    final fsrSize = Size(fsrW, fsrH);

    render(offlineCanvas, fsrSize, viewProjection: viewProjection);

    final picture = recorder.endRecording();
    return picture.toImageSync(fsrW.toInt(), fsrH.toInt());
  }

  /// Renders stereo: left eye then right eye, side by side.
  /// Renders offline, then applies FFR/FSR scaling, chromatic aberration, and ATW warping.
  /// Reuses cached image buffers if useATWFallback is true.
  void renderStereo(Canvas canvas, Size fullSize) {
    final halfWidth = fullSize.width / 2;
    final eyeSize = Size(halfWidth, fullSize.height);
    final aspect = halfWidth / fullSize.height;

    final Image leftImg;
    final Image rightImg;

    if (useATWFallback && _lastLeftImage != null && _lastRightImage != null) {
      // Re-use last frame's successfully rendered images
      leftImg = _lastLeftImage!;
      rightImg = _lastRightImage!;
    } else {
      // Render new images and update cache
      final newLeft = _renderEyeToImage(eyeSize, cameraRig.leftViewProjection(aspect));
      final newRight = _renderEyeToImage(eyeSize, cameraRig.rightViewProjection(aspect));

      _lastLeftImage?.dispose();
      _lastRightImage?.dispose();

      _lastLeftImage = newLeft;
      _lastRightImage = newRight;

      leftImg = newLeft;
      rightImg = newRight;
    }

    // Left eye (offline warp)
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, halfWidth, fullSize.height));
    _leftDistortionMesh.drawDistortedImage(
      canvas,
      leftImg,
      eyeSize,
      atwTransform: leftAtwMatrix,
      enableChromaticAberration: enableChromaticAberration,
    );
    canvas.restore();

    // Right eye (offline warp)
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(halfWidth, 0, halfWidth, fullSize.height));
    canvas.translate(halfWidth, 0);
    _rightDistortionMesh.drawDistortedImage(
      canvas,
      rightImg,
      eyeSize,
      atwTransform: rightAtwMatrix,
      enableChromaticAberration: enableChromaticAberration,
    );
    canvas.restore();

    // Clear fallback flag after frame completion
    useATWFallback = false;

    // Divider
    canvas.drawRect(
      Rect.fromLTWH(halfWidth - 2, 0, 4, fullSize.height),
      Paint()..color = const Color(0xFF000000),
    );
  }

  /// Renders monoscopic.
  void renderMono(Canvas canvas, Size size) {
    final aspect = size.width / size.height;
    render(canvas, size, viewProjection: cameraRig.monoViewProjection(aspect));
  }
}
