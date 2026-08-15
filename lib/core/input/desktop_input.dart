import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, KeyUpEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart' hide Matrix4;
import 'package:vector_math/vector_math.dart';

import '../../interaction/raycast.dart';
import '../../scene/node.dart';
import '../camera/camera_rig.dart';

/// Desktop input driver: mouse-look, WASD locomotion, and mouse-picking.
///
/// Designed for macOS / Windows / Linux targets where no gyroscope exists.
/// The driver is UI-toolkit agnostic: forward [KeyEvent]s and pointer deltas
/// from your widget tree (or use the included [DesktopInputRegion] wrapper),
/// and call [update] every frame ([VREngine] does this automatically when
/// enabled via `engine.enableDesktopInput()`).
///
/// ```dart
/// final driver = engine.enableDesktopInput();
///
/// DesktopInputRegion(
///   driver: driver,
///   child: CustomPaint(painter: engine.monoPainter),
/// );
/// ```
class DesktopInputDriver {
  final CameraRig cameraRig;

  /// Mouse-look sensitivity in radians per pixel dragged.
  double lookSensitivity;

  /// Locomotion speed in meters per second.
  double moveSpeed;

  /// Speed multiplier while a sprint key (Shift) is held.
  double sprintMultiplier;

  /// Inverts vertical mouse-look.
  bool invertY;

  /// Master switch — when false all input is ignored.
  bool enabled;

  // ─── Key bindings (rebindable) ──────────────────
  LogicalKeyboardKey keyForward;
  LogicalKeyboardKey keyBackward;
  LogicalKeyboardKey keyLeft;
  LogicalKeyboardKey keyRight;
  LogicalKeyboardKey keyUp;
  LogicalKeyboardKey keyDown;

  final Set<LogicalKeyboardKey> _pressedKeys = {};

  DesktopInputDriver({
    required this.cameraRig,
    this.lookSensitivity = 0.0035,
    this.moveSpeed = 3.0,
    this.sprintMultiplier = 2.5,
    this.invertY = false,
    this.enabled = true,
    this.keyForward = LogicalKeyboardKey.keyW,
    this.keyBackward = LogicalKeyboardKey.keyS,
    this.keyLeft = LogicalKeyboardKey.keyA,
    this.keyRight = LogicalKeyboardKey.keyD,
    this.keyUp = LogicalKeyboardKey.keyE,
    this.keyDown = LogicalKeyboardKey.keyQ,
  });

  /// Currently pressed movement keys (read-only view).
  Set<LogicalKeyboardKey> get pressedKeys => Set.unmodifiable(_pressedKeys);

  // ─── Mouse-look ──────────────────

  /// Applies a mouse pointer delta (in logical pixels) as camera rotation.
  ///
  /// Sign convention matches [HeadTracker.applyTouchDelta] (grab-the-world
  /// drag): dragging right rotates the view left.
  void handlePointerDelta(Offset delta) {
    if (!enabled) return;
    final dy = invertY ? delta.dy : -delta.dy;
    cameraRig.rotate(-delta.dx * lookSensitivity, dy * lookSensitivity);
  }

  // ─── Keyboard ──────────────────

  /// Tracks a key event. Returns true if the key is managed by this driver
  /// (movement or sprint keys), so the widget layer can mark it handled.
  bool handleKeyEvent(KeyEvent event) {
    if (!enabled) return false;

    final key = event.logicalKey;
    final managed = _isMovementKey(key) || _isSprintKey(key);
    if (!managed) return false;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _pressedKeys.add(key);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(key);
    }
    return true;
  }

  bool _isMovementKey(LogicalKeyboardKey key) =>
      key == keyForward ||
      key == keyBackward ||
      key == keyLeft ||
      key == keyRight ||
      key == keyUp ||
      key == keyDown;

  bool _isSprintKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight;

  /// Releases all pressed keys (call when the window loses focus).
  void releaseAllKeys() => _pressedKeys.clear();

  // ─── Locomotion ──────────────────

  /// Applies WASD locomotion for frame time [dt] (seconds).
  /// Movement is relative to the camera's yaw (ground-plane projection).
  /// Called automatically by [VREngine] each tick when enabled.
  void update(double dt) {
    if (!enabled || _pressedKeys.isEmpty) return;

    var ix = 0.0;
    var iz = 0.0;
    var iy = 0.0;
    if (_pressedKeys.contains(keyForward)) iz += 1;
    if (_pressedKeys.contains(keyBackward)) iz -= 1;
    if (_pressedKeys.contains(keyRight)) ix += 1;
    if (_pressedKeys.contains(keyLeft)) ix -= 1;
    if (_pressedKeys.contains(keyUp)) iy += 1;
    if (_pressedKeys.contains(keyDown)) iy -= 1;
    if (ix == 0 && iz == 0 && iy == 0) return;

    final sprinting = _pressedKeys.any(_isSprintKey);
    final speed = moveSpeed * (sprinting ? sprintMultiplier : 1.0);

    // Ground-plane forward/right from camera yaw
    final fwd = cameraRig.headTransform.forward.clone()..y = 0;
    if (fwd.length2 < 1e-8) {
      fwd.setValues(0, 0, -1); // Looking straight up/down: use default forward
    } else {
      fwd.normalize();
    }
    final right = fwd.cross(Vector3(0, 1, 0))..normalize();

    final move = (fwd * iz + right * ix + Vector3(0, iy, 0));
    if (move.length2 > 1.0) move.normalize();

    cameraRig.position += move * speed * dt;
  }

  // ─── Mouse picking ──────────────────

  /// Unprojects a screen point (logical pixels within [viewport]) into a
  /// world-space ray using the monoscopic view-projection — the desktop
  /// equivalent of [GazePointer.ray].
  Ray screenPointToRay(Offset point, Size viewport) {
    final aspect = viewport.width / viewport.height;
    final inv = Matrix4.tryInvert(cameraRig.monoViewProjection(aspect));
    if (inv == null) {
      // Degenerate matrix: fall back to camera axes
      return Ray.originDirection(
        cameraRig.position.clone(),
        cameraRig.headTransform.forward,
      );
    }

    final ndx = 2.0 * point.dx / viewport.width - 1.0;
    final ndy = 1.0 - 2.0 * point.dy / viewport.height;

    final nearH = inv.transform(Vector4(ndx, ndy, -1, 1));
    final farH = inv.transform(Vector4(ndx, ndy, 1, 1));
    final nearP = Vector3(
      nearH.x / nearH.w,
      nearH.y / nearH.w,
      nearH.z / nearH.w,
    );
    final farP = Vector3(farH.x / farH.w, farH.y / farH.w, farH.z / farH.w);

    final dir = farP - nearP;
    if (dir.length2 < 1e-12) {
      return Ray.originDirection(nearP, cameraRig.headTransform.forward);
    }
    dir.normalize();
    return Ray.originDirection(nearP, dir);
  }

  /// Picks the nearest scene node under the mouse cursor.
  RaycastHit? pick(
    Offset point,
    Size viewport,
    Node root, {
    double maxDistance = double.infinity,
  }) {
    if (!enabled) return null;
    final ray = screenPointToRay(point, viewport);
    return Raycaster().castNearest(ray, root, maxDistance: maxDistance);
  }
}

/// Widget wrapper that forwards mouse and keyboard input to a
/// [DesktopInputDriver]. Place it around the VR viewport on desktop targets.
///
/// - **Mouse-look**: hold the primary button and drag.
/// - **Click-to-pick**: [onPick] fires with the raycast hit (if any).
/// - **Keyboard**: WASD + Q/E vertical + Shift sprint (auto-focused).
class DesktopInputRegion extends StatefulWidget {
  final DesktopInputDriver driver;
  final Widget child;

  /// Called when the user clicks; receives the nearest hit (or null).
  final void Function(RaycastHit? hit)? onPick;

  /// Called continuously while the pointer moves (for hover effects).
  final void Function(Ray ray, Offset position)? onHoverRay;

  /// Scene root used for [onPick] raycasts.
  final Node? pickRoot;

  const DesktopInputRegion({
    super.key,
    required this.driver,
    required this.child,
    this.onPick,
    this.onHoverRay,
    this.pickRoot,
  });

  @override
  State<DesktopInputRegion> createState() => _DesktopInputRegionState();
}

class _DesktopInputRegionState extends State<DesktopInputRegion> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final handled = widget.driver.handleKeyEvent(event);
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (widget.driver.enabled &&
        (event.buttons & kPrimaryButton) != 0 &&
        event.delta != Offset.zero) {
      widget.driver.handlePointerDelta(event.delta);
    }
    widget.onHoverRay?.call(
      widget.driver.screenPointToRay(event.localPosition, size),
      event.localPosition,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Listener(
            onPointerDown: (event) {
              _focusNode.requestFocus();
              if (widget.onPick != null && widget.pickRoot != null) {
                final hit = widget.driver.pick(
                  event.localPosition,
                  size,
                  widget.pickRoot!,
                );
                widget.onPick!(hit);
              }
            },
            onPointerMove: (event) => _onPointerMove(event, size),
            child: widget.child,
          ),
        );
      },
    );
  }
}
