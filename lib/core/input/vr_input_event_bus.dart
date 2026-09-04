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

  /// Bluetooth, USB, or platform gamepad.
  gamepad,

  /// Community-provided peripheral without a more specific source.
  externalPeripheral,
}

/// Unified spatial input event.
///
/// Events can be reused by [VrInputArbiter]'s pool. Consumers must treat an
/// event received from the arbiter as borrowed memory: read it synchronously
/// and do not retain it after the callback returns. Code that needs to keep an
/// event should copy the required scalar values instead.
class VrInputEvent {
  VrInputType _type;
  VrInputSource _source;
  String? _targetId;
  Map<String, dynamic>? _data;
  bool _active;
  int _timestampMicrosecondsSinceEpoch;

  VrInputType get type => _type;
  VrInputSource get source => _source;
  String? get targetId => _targetId;
  Map<String, dynamic>? get data => _data;

  /// Whether the source is actively manipulated.
  ///
  /// A joystick outside its dead zone or a touch-down is active. A centered
  /// joystick or touch-up is inactive and does not extend arbitration
  /// hysteresis.
  bool get active => _active;

  /// Allocation-free timestamp used by high-frequency input paths.
  int get timestampMicrosecondsSinceEpoch => _timestampMicrosecondsSinceEpoch;

  /// Wall-clock timestamp for compatibility and diagnostics.
  ///
  /// Accessing this getter creates a [DateTime]. Hot paths should prefer
  /// [timestampMicrosecondsSinceEpoch].
  DateTime get timestamp =>
      DateTime.fromMicrosecondsSinceEpoch(_timestampMicrosecondsSinceEpoch);

  VrInputEvent({
    required VrInputType type,
    required VrInputSource source,
    String? targetId,
    Map<String, dynamic>? data,
    bool active = true,
    DateTime? timestamp,
  }) : _type = type,
       _source = source,
       _targetId = targetId,
       _data = data,
       _active = active,
       _timestampMicrosecondsSinceEpoch =
           (timestamp ?? DateTime.now()).microsecondsSinceEpoch;

  /// Reinitializes this instance for an event pool.
  ///
  /// Application code normally uses [VrInputEventPool.acquire] instead of
  /// calling this directly.
  void resetForReuse({
    required VrInputType type,
    required VrInputSource source,
    required int timestampMicrosecondsSinceEpoch,
    String? targetId,
    Map<String, dynamic>? data,
    bool active = true,
  }) {
    _type = type;
    _source = source;
    _targetId = targetId;
    _data = data;
    _active = active;
    _timestampMicrosecondsSinceEpoch = timestampMicrosecondsSinceEpoch;
  }

  /// Drops references before this event returns to a pool.
  void clearForReuse() {
    _targetId = null;
    _data = null;
    _active = false;
    _timestampMicrosecondsSinceEpoch = 0;
  }

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
