import 'dart:async';

import 'package:vector_math/vector_math.dart';

import '../../scene/scene.dart';
import '../../scene/vr_controller_avatar_node.dart';
import '../../scene/vr_controller_arm_model.dart';
import '../camera/camera_rig.dart';
import '../input/controller_state.dart';
import '../input/drivers/vr_laser_pointer_driver.dart';
import '../input/drivers/vr_remote_touchpad_driver.dart';
import '../input/vr_input_arbiter.dart';
import '../input/vr_input_event_bus.dart';
import 'vr_controller_protocol.dart';
import 'vr_controller_transport.dart';
import 'vr_remote_pose_predictor.dart';

/// Parent-side bridge from a paired controller transport into input and scene.
class VrRemoteControllerSession {
  final VrControllerTransport transport;
  final VrInputArbiter arbiter;
  final CameraRig cameraRig;
  final Scene? scene;
  final VrLaserPointerDriver pointerDriver;
  final VrRemoteTouchpadDriver touchpadDriver;
  final VrRemotePosePredictor posePredictor;

  final Quaternion _orientation = Quaternion.identity();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  VrControllerProfile? _profile;
  VrControllerAvatarNode? _avatar;
  ControllerState? _controllerState;
  int _lastSequence = -1;
  int _triggerMask = 4;
  bool _lastTriggerPressed = false;
  bool _started = false;

  VrRemoteControllerSession({
    required this.transport,
    required this.arbiter,
    required this.cameraRig,
    this.scene,
    VrLaserPointerDriver? pointerDriver,
    VrRemoteTouchpadDriver? touchpadDriver,
    VrRemotePosePredictor? posePredictor,
  }) : pointerDriver = pointerDriver ?? VrLaserPointerDriver(),
       touchpadDriver = touchpadDriver ?? VrRemoteTouchpadDriver(),
       posePredictor = posePredictor ?? VrRemotePosePredictor();

  bool get isStarted => _started;
  VrControllerProfile? get profile => _profile;
  VrControllerAvatarNode? get avatar => _avatar;
  ControllerState? get controllerState => _controllerState;
  int get lastSequence => _lastSequence;
  Duration get roundTripLatency => posePredictor.roundTripLatency;

  void start() {
    if (_started) return;
    try {
      arbiter.attachDriver(pointerDriver);
      arbiter.attachDriver(touchpadDriver);
      _subscriptions
        ..add(transport.onProfile.listen(_handleProfile))
        ..add(transport.onPose.listen(_handlePose))
        ..add(transport.onEvent.listen(_handleInputEvent))
        ..add(transport.onState.listen(_handleTransportState))
        ..add(transport.onLatency.listen(posePredictor.updateLatency));
      _started = true;
    } catch (_) {
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      _subscriptions.clear();
      if (touchpadDriver.isAttached) arbiter.detachDriver(touchpadDriver);
      if (pointerDriver.isAttached) arbiter.detachDriver(pointerDriver);
      rethrow;
    }
  }

  void recenter() => pointerDriver.recenter();

  void _handleProfile(VrControllerProfile profile) {
    touchpadDriver.updateTouch(null, null);
    if (_lastTriggerPressed) pointerDriver.setTrigger(false);
    _profile = profile;
    _lastSequence = -1;
    _triggerMask = _maskForControlKind(profile, VrControlKind.trigger) ?? 4;
    _lastTriggerPressed = false;
    posePredictor.reset();
    _avatar?.removeFromParent();
    final avatar = VrControllerAvatarNode(
      profile: profile,
      cameraRig: cameraRig,
      armModel: VrControllerArmModel(handedness: profile.handedness),
    );
    final connected = transport.state == VrTransportConnectionState.connected;
    avatar.visible = connected;
    _avatar = avatar;
    scene?.add(avatar);
    _controllerState = ControllerState(
      hand: switch (profile.handedness) {
        VrControllerHandedness.left => ControllerHand.left,
        VrControllerHandedness.right ||
        VrControllerHandedness.unspecified => ControllerHand.right,
      },
      connected: connected,
    );
  }

  void _handlePose(VrRemotePoseFrame frame) {
    if (frame.sequence <= _lastSequence) return;
    _lastSequence = frame.sequence;
    posePredictor.pushFrame(frame);
    updatePosePrediction();

    final triggerPressed = frame.buttonsBitset & _triggerMask != 0;
    if (triggerPressed != _lastTriggerPressed) {
      _lastTriggerPressed = triggerPressed;
      pointerDriver.setTrigger(triggerPressed);
    }
    touchpadDriver.updateTouch(frame.touchX, frame.touchY);

    final corrected = pointerDriver.orientation;
    final state = _controllerState;
    if (state != null) {
      state.transform.setRotationFrom(corrected);
      state.connected = true;
      state.primaryButtonPressed = frame.buttonsBitset & 1 != 0;
      state.secondaryButtonPressed = frame.buttonsBitset & 2 != 0;
      state.triggerPressed = triggerPressed;
      state.triggerValue = state.triggerPressed ? 1 : 0;
      state.thumbstick.setValues(touchpadDriver.axisX, touchpadDriver.axisY);
    }

    _avatar
      ?..visible = true
      ..updateButtons(frame.buttonsBitset)
      ..updateRange(
        meters: frame.rangeMeters,
        source: frame.rangeSource,
        confidence: frame.rangeConfidence,
      );
  }

  /// Reprojects the latest pose for the current render time.
  ///
  /// Call once before rendering each frame to keep prediction current even
  /// between network packets. Incoming packets invoke this automatically too.
  bool updatePosePrediction() {
    if (!posePredictor.predictTo(_orientation)) return false;
    pointerDriver.updateOrientation(_orientation);
    final corrected = pointerDriver.orientation;
    _controllerState?.transform.setRotationFrom(corrected);
    _avatar?.updateOrientation(corrected);
    return true;
  }

  void _handleInputEvent(VrInputEvent event) {
    arbiter.submit(event);
    final state = _controllerState;
    if (state == null) return;
    if (event.type == VrInputType.trigger) {
      _lastTriggerPressed = event.active;
      state.triggerPressed = event.active;
      state.triggerValue = event.active ? 1 : 0;
    }
  }

  void _handleTransportState(VrTransportConnectionState state) {
    final connected = state == VrTransportConnectionState.connected;
    final controller = _controllerState;
    if (controller != null) {
      controller.connected = connected;
      if (!connected) {
        controller.triggerPressed = false;
        controller.triggerValue = 0;
        controller.thumbstick.setZero();
      }
    }
    if (_avatar != null) _avatar!.visible = connected;
    if (!connected) {
      touchpadDriver.updateTouch(null, null);
      if (_lastTriggerPressed) {
        _lastTriggerPressed = false;
        pointerDriver.setTrigger(false);
      }
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    touchpadDriver.updateTouch(null, null);
    if (_lastTriggerPressed) pointerDriver.setTrigger(false);
    if (touchpadDriver.isAttached) arbiter.detachDriver(touchpadDriver);
    if (pointerDriver.isAttached) arbiter.detachDriver(pointerDriver);
    _avatar?.removeFromParent();
    _avatar = null;
    _controllerState?.connected = false;
  }

  static int? _maskForControlKind(
    VrControllerProfile profile,
    VrControlKind kind,
  ) {
    for (var index = 0; index < profile.controls.length; index++) {
      if (profile.controls[index].kind == kind) return 1 << index;
    }
    return null;
  }
}
