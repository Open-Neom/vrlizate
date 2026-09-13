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
import '../input/vr_input_arbiter.dart';
import '../input/vr_input_event_bus.dart';
import '../input/vr_spatial_input_state.dart';
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
  final VrSpatialInputState spatialInput = VrSpatialInputState();
  final Ray _interactionRay = Ray();
  bool _hasExternalInteractionRay = false;

  /// A spatial renderer can reserve dwell for its own world-space controls.
  bool externalDwellSuppressed = false;
  final Vector3 _inputDisplacement = Vector3.zero();
  VrInputArbiter? _inputArbiter;
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

  /// Publishes an explicit game action without advancing simulation time.
  void notifyGameStateChanged() => notifyListeners();

  /// Shares arbitration and pointer state with the host; does not own it.
  void bindInput(VrInputArbiter? arbiter) {
    if (identical(arbiter, _inputArbiter)) return;
    _inputArbiter?.removeListener(_onInput);
    _inputArbiter = arbiter;
    spatialInput.reset();
    arbiter?.addListener(_onInput);
  }

  void _onInput(VrInputEvent event) {
    spatialInput.handleEvent(event);
    if (event.type == VrInputType.recenter && event.active && !event.handled) {
      headTracker?.recenter();
      cameraRig.recenter();
      event.consume();
    }
  }

  bool get isDwellEnabled =>
      !externalDwellSuppressed &&
      !spatialInput.pointerActive &&
      !(_inputArbiter?.isGazeSuppressed ?? false);

  /// Borrowed world ray shared by gameplay and explicit selection.
  Ray get interactionRay {
    if (_hasExternalInteractionRay) return _interactionRay;
    spatialInput.writeRay(
      _interactionRay,
      origin: cameraRig.position,
      forward: cameraRig.headTransform.forward,
      screenRight: cameraRig.headTransform.right,
      up: cameraRig.headTransform.up,
    );
    return _interactionRay;
  }

  /// Copies a renderer's current ray. Passing null restores the core ray.
  /// This avoids retaining a borrowed/pooled input object across frames.
  void setExternalInteractionRay(Ray? ray) {
    _hasExternalInteractionRay = ray != null;
    if (ray != null) {
      _interactionRay.origin.setFrom(ray.origin);
      _interactionRay.direction.setFrom(ray.direction);
    }
  }

  /// Transfers frame and sensor ownership to an external spatial renderer.
  /// Game rules and the source scene remain available through [step].
  void useExternalFrameDriver() {
    stop();
    disableHeadTracking();
    disableInertialTap();
    disableDesktopInput();
  }

  /// Integrates held input once per rendered frame. Public for headless hosts.
  void updateInput(double dt) {
    spatialInput.update(dt);
    if (!dt.isFinite || dt <= 0 || dt > 0.25) return;
    if (spatialInput.lookX != 0 || spatialInput.lookY != 0) {
      cameraRig.rotate(
        spatialInput.lookX * 2.1 * dt,
        -spatialInput.lookY * 1.5 * dt,
      );
    }
    if (spatialInput.moveX == 0 && spatialInput.moveY == 0) return;
    spatialInput.writeMovement(
      _inputDisplacement,
      forward: cameraRig.headTransform.forward,
      screenRight: cameraRig.headTransform.right,
      dt: dt,
    );
    cameraRig.position.add(_inputDisplacement);
  }

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
      final hit = _nearestPointableHit();
      gazePointer!.triggerTap(hit);
    }
  }

  RaycastHit? _nearestPointableHit() {
    final pointer = gazePointer;
    if (pointer == null) return null;

    for (final hit in _raycaster.cast(interactionRay, scene.root)) {
      if (hit.node.pointable != null) return hit;
    }
    return null;
  }

  /// Enables zero-latency temple/visor physical tap detection.
  void enableInertialTap({
    VoidCallback? onSingleTap,
    VoidCallback? onDoubleTap,
  }) {
    inertialTapDetector?.dispose();
    inertialTapDetector = InertialTapDetector(
      onSingleTap: onSingleTap ?? handleTap,
      onDoubleTap:
          onDoubleTap ??
          () {
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
    step(dt);
  }

  /// Advances simulation without drawing or scheduling another frame.
  ///
  /// External GPU hosts pass [integrateInput] false: their renderer owns
  /// locomotion, tracking and the active ray, so input is never applied twice.
  void step(double dt, {bool integrateInput = true}) {
    if (!dt.isFinite || dt <= 0) return;
    dt = dt.clamp(0.0, 0.1);
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

    if (integrateInput) updateInput(dt);
    if (!integrateInput) spatialInput.update(dt);

    // Update scene
    scene.update(dt);

    // Update gaze pointer and interactables if active
    if (gazePointer != null) {
      final pointer = gazePointer!;
      final hit = _nearestPointableHit();
      final progressBeforeUpdate = pointer.dwellProgress;
      pointer.update(dt, hit?.node.name, dwellEnabled: isDwellEnabled);

      // Dwell selection activates the same Pointable used by a physical tap.
      if (hit != null &&
          progressBeforeUpdate < 1 &&
          pointer.dwellProgress >= 1) {
        hit.node.pointable?.press(hit);
        Future.delayed(const Duration(milliseconds: 100), () {
          hit.node.pointable?.release();
        });
      }

      // Traversal to update Pointable hover states
      scene.root.traverse((node) {
        if (node.pointable != null) {
          final isGazingThisNode = hit != null && hit.node == node;
          node.pointable!.updateHover(isGazingThisNode);
        }
      });
    }

    // Update desktop locomotion (WASD) if active
    if (integrateInput) desktopInput?.update(dt);

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
    bindInput(null);
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

  @override
  void setOrientation(double yaw, double pitch) =>
      rig.setOrientation(yaw, pitch);

  @override
  void setPitch(double pitch) => rig.setPitch(pitch);
}
