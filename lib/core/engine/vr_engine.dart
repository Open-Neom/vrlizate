import 'dart:async';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show CustomPainter, ChangeNotifier;
import 'package:vector_math/vector_math.dart';

import '../../scene/scene.dart';
import '../camera/camera_rig.dart';
import '../input/desktop_input.dart';
import '../input/head_tracker.dart';
import '../input/gaze_pointer.dart';
import '../input/inertial_tap_detector.dart';
import '../rendering/render_pass.dart';
import '../../interaction/raycast.dart';

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
class VREngine extends ChangeNotifier {
  final Scene scene;
  final CameraRig cameraRig;
  late final RenderPass renderPass;
  HeadTracker? headTracker;
  GazePointer? gazePointer;
  DesktopInputDriver? desktopInput;
  InertialTapDetector? inertialTapDetector;
  final Raycaster _raycaster = Raycaster();
  Quaternion? _lastCameraRotation;

  Timer? _timer;
  Ticker? _ticker;
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

  /// Starts the game loop, synchronized to the display's vsync when a
  /// [SchedulerBinding] is available (less jitter → less VR motion sickness
  /// than a fixed 16ms timer). Falls back to a ~60fps timer in headless
  /// environments (tests, isolates without a binding).
  void start() {
    if (_running) return;
    _running = true;
    _lastTime = DateTime.now();
    try {
      _ticker = Ticker((_) => _tick())..start();
    } catch (_) {
      _ticker = null;
      _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    }
  }

  /// Stops the game loop.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _ticker?.stop();
  }

  /// Enables gyroscope head tracking.
  /// [sensitivity] 1.0 (default) = true 1:1 tracking, ideal for VR.
  void enableHeadTracking({double sensitivity = 1.0}) {
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

  /// Enables gaze-based interaction pointer (look-to-select).
  void enableGazePointer({double dwellDuration = 2.0}) {
    gazePointer = GazePointer(
      cameraRig: cameraRig,
      dwellDuration: dwellDuration,
    );
  }

  /// Disables the gaze pointer.
  void disableGazePointer() {
    gazePointer = null;
  }

  /// Enables desktop input (mouse-look, WASD locomotion, mouse-picking).
  /// Returns the driver so the widget layer can forward pointer/key events
  /// (see [DesktopInputRegion]).
  DesktopInputDriver enableDesktopInput({
    double lookSensitivity = 0.0035,
    double moveSpeed = 3.0,
    double sprintMultiplier = 2.5,
  }) {
    desktopInput = DesktopInputDriver(
      cameraRig: cameraRig,
      lookSensitivity: lookSensitivity,
      moveSpeed: moveSpeed,
      sprintMultiplier: sprintMultiplier,
    );
    return desktopInput!;
  }

  /// Disables desktop input.
  void disableDesktopInput() {
    desktopInput?.releaseAllKeys();
    desktopInput = null;
  }

  /// Exposes screen tap event (e.g. Cardboard viewer button click)
  /// and propagates it to the gazed interactive target.
  void handleTap() {
    if (gazePointer != null) {
      final ray = gazePointer!.ray;
      final hit = _raycaster.castNearest(ray, scene.root);
      gazePointer!.triggerTap(hit);
    }
  }

  /// Enables zero-latency temple/visor physical tap detection.
  void enableInertialTap({
    VoidCallback? onSingleTap,
    VoidCallback? onDoubleTap,
  }) {
    inertialTapDetector?.dispose();
    inertialTapDetector = InertialTapDetector(
      onSingleTap: onSingleTap ?? handleTap,
      onDoubleTap: onDoubleTap ?? () {
        headTracker?.recenter();
        cameraRig.recenter();
      },
    )..start();
  }

  /// Disables inertial tap detector.
  void disableInertialTap() {
    inertialTapDetector?.dispose();
    inertialTapDetector = null;
  }

  void _tick() {
    final now = DateTime.now();
    final dt = now.difference(_lastTime).inMicroseconds / 1000000.0;
    _lastTime = now;
    _frameCount++;

    // FPS calculation (smoothed)
    _frameTime = dt * 1000;
    _fps = _fps * 0.9 + (1.0 / dt) * 0.1;

    // Asynchronous Time Warp (ATW) Check:
    // If the frame time is above 18ms (frame drop), calculate rotation delta and set ATW matrices
    final currentRotation = cameraRig.rotation;
    if (_frameTime > 18.0 && _lastCameraRotation != null) {
      final delta = currentRotation * _lastCameraRotation!.inverted();
      final atwMatrix = Matrix4.compose(
        Vector3.zero(),
        delta,
        Vector3.all(1.0),
      );
      renderPass.leftAtwMatrix = atwMatrix;
      renderPass.rightAtwMatrix = atwMatrix;
      renderPass.useATWFallback = true;
    } else {
      renderPass.leftAtwMatrix = null;
      renderPass.rightAtwMatrix = null;
      renderPass.useATWFallback = false;
    }
    _lastCameraRotation = currentRotation.clone();

    // Update scene
    scene.update(dt);

    // Update gaze pointer and interactables if active
    if (gazePointer != null) {
      final ray = gazePointer!.ray;
      final hit = _raycaster.castNearest(ray, scene.root);
      gazePointer!.update(dt, hit?.node.name);

      // Traversal to update Pointable hover states
      scene.root.traverse((node) {
        if (node.pointable != null) {
          final isGazingThisNode = hit != null && hit.node == node;
          node.pointable!.updateHover(isGazingThisNode);
        }
      });
    }

    // Update desktop locomotion (WASD) if active
    desktopInput?.update(dt);

    // Custom update callback
    onUpdate?.call(dt);

    // Notify the CustomPainter to redraw!
    notifyListeners();
  }

  /// Creates a CustomPainter that renders stereoscopically.
  VREnginePainter get stereoPainter => VREnginePainter._(this, stereo: true);

  /// Creates a CustomPainter that renders monoscopically.
  VREnginePainter get monoPainter => VREnginePainter._(this, stereo: false);

  @override
  void dispose() {
    stop();
    _ticker?.dispose();
    headTracker?.dispose();
    inertialTapDetector?.dispose();
    super.dispose();
  }

  // Bridge to the old VRCamera API for HeadTracker compatibility
  _HeadTrackerBridge get _headTrackerCamera => _HeadTrackerBridge(cameraRig);
}

/// CustomPainter that renders the VR engine output.
class VREnginePainter extends CustomPainter {
  final VREngine _engine;
  final bool _stereo;

  VREnginePainter._(this._engine, {required bool stereo})
    : _stereo = stereo,
      super(repaint: _engine);

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

  @override
  void recenter() => rig.recenter();
}
