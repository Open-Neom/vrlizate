import 'dart:async';

/// Canonical input interaction types across VRlizate XR experiences.
enum VrInputType {
  /// Primary selection action (e.g. dwell trigger, tap, controller trigger, voice "abrir").
  select,

  /// Secondary or backward action (e.g. back button, voice "home", exit app).
  back,

  /// Navigation or teleportation in 3D space (e.g. arc jump, voice "ir a norte").
  navigate,

  /// Hovering or aiming at a spatial element (e.g. laser ray hit, gaze focus).
  hover,

  /// Continuous trigger state change (press / release).
  trigger,

  /// Finger pinch gesture from optical hand tracking.
  pinch,
}

/// Hardware or software source that originated the input event.
enum VrInputSource {
  /// Temple tap detection via IMU accelerometer spike.
  templeTap,

  /// 2nd smartphone 3DoF laser remote controller.
  remotePhone,

  /// Hands-free voice recognition / Itzli AI assistant.
  voice,

  /// Center gaze dwell pointer.
  gaze,

  /// Ultrasonic Doppler acoustic gesture (19.2 kHz).
  sonar,

  /// Computer vision optical hand tracking.
  cameraHand,

  /// Direct touchscreen touch.
  touch,
}

/// Unified spatial input event.
class VrInputEvent {
  final VrInputType type;
  final VrInputSource source;
  final String? targetId;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  VrInputEvent({
    required this.type,
    required this.source,
    this.targetId,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'VrInputEvent(type: $type, source: $source, targetId: $targetId)';
}

/// Central Event Bus for unified multimodal spatial input in VRlizate.
///
/// Decouples raw hardware sensors (IMU, camera, microphone, ultrasound, remote phone)
/// from 3D scenes, allowing any scene to respond to spatial inputs agnostically.
class VrInputEventBus {
  static final VrInputEventBus _instance = VrInputEventBus._internal();
  static VrInputEventBus get instance => _instance;

  final StreamController<VrInputEvent> _controller =
      StreamController<VrInputEvent>.broadcast();

  VrInputEventBus._internal();

  /// Stream of all spatial input events.
  Stream<VrInputEvent> get onEvent => _controller.stream;

  /// Emits a new spatial input event to all subscribers.
  void emit(VrInputEvent event) {
    _controller.add(event);
  }

  /// Convenience stream filtered by [VrInputType].
  Stream<VrInputEvent> onType(VrInputType type) =>
      _controller.stream.where((e) => e.type == type);

  /// Convenience stream filtered by [VrInputSource].
  Stream<VrInputEvent> onSource(VrInputSource source) =>
      _controller.stream.where((e) => e.source == source);
}
