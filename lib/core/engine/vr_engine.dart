import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart' show CustomPainter;

import '../../scene/scene.dart';
import '../camera/camera_rig.dart';
import '../input/head_tracker.dart';
import '../rendering/render_pass.dart';

/// Main VR engine. Manages the game loop, scene, camera, and rendering.
///
/// ```dart
/// final engine = VREngine();
/// engine.scene.add(myMesh);
/// engine.start();
///
/// // In your widget:
/// CustomPaint(painter: engine.stereoPainter)
/// ```
class VREngine {
  final Scene scene;
  final CameraRig cameraRig;
  late final RenderPass renderPass;
  HeadTracker? headTracker;

  Timer? _timer;
  DateTime _lastTime = DateTime.now();
  bool _running = false;
  int _frameCount = 0;
  double _fps = 0;
  double _frameTime = 0;

  /// Callback fired each frame after update.
  void Function(double dt)? onUpdate;

  VREngine({Scene? scene, CameraRig? cameraRig})
    : scene = scene ?? Scene(),
      cameraRig = cameraRig ?? CameraRig() {
    renderPass = RenderPass(scene: this.scene, cameraRig: this.cameraRig);
  }

  bool get isRunning => _running;
  double get fps => _fps;
  double get frameTimeMs => _frameTime;
  int get frameCount => _frameCount;
  int get culledCount => renderPass.culledCount;
  int get renderedCount => renderPass.renderedCount;

  /// Starts the game loop at ~60fps.
  void start() {
    if (_running) return;
    _running = true;
    _lastTime = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  /// Stops the game loop.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Enables gyroscope head tracking.
  void enableHeadTracking({double sensitivity = 0.03}) {
    headTracker?.dispose();
    headTracker = HeadTracker(
      target: _headTrackerCamera,
      sensitivity: sensitivity,
    );
    headTracker!.start();
  }

  /// Disables head tracking.
  void disableHeadTracking() {
    headTracker?.dispose();
    headTracker = null;
  }

  void _tick() {
    final now = DateTime.now();
    final dt = now.difference(_lastTime).inMicroseconds / 1000000.0;
    _lastTime = now;
    _frameCount++;

    // FPS calculation (smoothed)
    _frameTime = dt * 1000;
    _fps = _fps * 0.9 + (1.0 / dt) * 0.1;

    // Update scene
    scene.update(dt);

    // Custom update callback
    onUpdate?.call(dt);
  }

  /// Creates a CustomPainter that renders stereoscopically.
  VREnginePainter get stereoPainter => VREnginePainter._(this, stereo: true);

  /// Creates a CustomPainter that renders monoscopically.
  VREnginePainter get monoPainter => VREnginePainter._(this, stereo: false);

  void dispose() {
    stop();
    headTracker?.dispose();
  }

  // Bridge to the old VRCamera API for HeadTracker compatibility
  _HeadTrackerBridge get _headTrackerCamera => _HeadTrackerBridge(cameraRig);
}

/// CustomPainter that renders the VR engine output.
class VREnginePainter extends CustomPainter {
  final VREngine _engine;
  final bool _stereo;

  VREnginePainter._(this._engine, {required bool stereo}) : _stereo = stereo;

  @override
  void paint(Canvas canvas, Size size) {
    if (_stereo) {
      _engine.renderPass.renderStereo(canvas, size);
    } else {
      _engine.renderPass.renderMono(canvas, size);
    }
  }

  @override
  bool shouldRepaint(VREnginePainter oldDelegate) => true;
}

/// Bridge class to make CameraRig compatible with HeadTracker's VRCamera interface.
class _HeadTrackerBridge implements RotationTarget {
  final CameraRig rig;
  _HeadTrackerBridge(this.rig);

  @override
  void rotate(double dTheta, double dPhi) {
    rig.rotate(dTheta, dPhi);
  }

  @override
  void reset() => rig.reset();
}
