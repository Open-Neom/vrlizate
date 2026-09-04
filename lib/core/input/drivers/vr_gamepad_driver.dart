import '../vr_input_arbiter.dart';
import '../vr_input_event_bus.dart';

/// Standard face buttons and analog triggers exposed by a gamepad adapter.
enum VrGamepadButton { a, b, x, y, l2, r2 }

/// Standard analog sticks.
enum VrGamepadStick { left, right }

/// Reference adapter from normalized gamepad state to canonical VR input.
///
/// Platform integrations only need to forward button, trigger, and stick
/// updates to this class. The mapping is intentionally stable:
///
/// - A press -> [VrInputType.select]
/// - B press -> [VrInputType.back]
/// - X/Y press and release -> [VrInputType.trigger]
/// - L2/R2 analog values -> [VrInputType.trigger]
/// - Left/right stick values -> [VrInputType.navigate]
///
/// Payload maps are allocated once and reused. [VrInputSink.emit] borrows and
/// releases a pooled [VrInputEvent] synchronously, so the driver does not
/// allocate an event for each 60-120 Hz update.
class VrGamepadDriver implements VrInputDriver {
  /// Payload key containing a [VrGamepadButton].
  static const String buttonKey = 'button';

  /// Payload key containing a [VrGamepadStick].
  static const String stickKey = 'stick';

  /// Payload key containing a normalized analog or digital value.
  static const String valueKey = 'value';

  /// Payload key containing a button/trigger pressed state.
  static const String pressedKey = 'pressed';

  /// Payload keys containing normalized stick axes in the -1..1 range.
  static const String xKey = 'x';
  static const String yKey = 'y';

  /// Radial deadzone applied to analog sticks.
  final double stickDeadzone;

  /// Threshold below which an analog trigger is considered inactive.
  final double triggerDeadzone;

  final Map<String, dynamic> _buttonPayload = <String, dynamic>{
    buttonKey: VrGamepadButton.a,
    valueKey: 0.0,
    pressedKey: false,
  };
  final Map<String, dynamic> _triggerPayload = <String, dynamic>{
    buttonKey: VrGamepadButton.l2,
    valueKey: 0.0,
    pressedKey: false,
  };
  final Map<String, dynamic> _stickPayload = <String, dynamic>{
    stickKey: VrGamepadStick.left,
    xKey: 0.0,
    yKey: 0.0,
  };

  VrInputSink? _sink;

  VrGamepadDriver({this.stickDeadzone = 0.15, this.triggerDeadzone = 0.05}) {
    if (stickDeadzone < 0 || stickDeadzone >= 1) {
      throw ArgumentError.value(
        stickDeadzone,
        'stickDeadzone',
        'Must be in the range 0 <= value < 1.',
      );
    }
    if (triggerDeadzone < 0 || triggerDeadzone >= 1) {
      throw ArgumentError.value(
        triggerDeadzone,
        'triggerDeadzone',
        'Must be in the range 0 <= value < 1.',
      );
    }
  }

  @override
  VrInputSource get source => VrInputSource.gamepad;

  bool get isAttached => _sink != null;

  @override
  void attach(VrInputSink sink) {
    if (_sink != null) {
      throw StateError('VrGamepadDriver is already attached.');
    }
    _sink = sink;
  }

  @override
  void detach() {
    _sink = null;
  }

  /// Forwards a digital button edge.
  ///
  /// A and B are discrete actions and emit only on press. X and Y emit both
  /// edges so consumers can observe their complete trigger state. Digital L2
  /// and R2 values are forwarded through [updateTrigger]. Returns whether an
  /// event reached the arbiter; returns `false` while detached.
  bool updateButton(VrGamepadButton button, bool pressed) {
    if (button == VrGamepadButton.l2 || button == VrGamepadButton.r2) {
      return updateTrigger(button, pressed ? 1 : 0);
    }

    final sink = _sink;
    if (sink == null) return false;

    final type = switch (button) {
      VrGamepadButton.a => VrInputType.select,
      VrGamepadButton.b => VrInputType.back,
      VrGamepadButton.x || VrGamepadButton.y => VrInputType.trigger,
      VrGamepadButton.l2 || VrGamepadButton.r2 => throw StateError(
        'Analog triggers are handled before this switch.',
      ),
    };

    if (!pressed &&
        (button == VrGamepadButton.a || button == VrGamepadButton.b)) {
      return false;
    }

    _buttonPayload[buttonKey] = button;
    _buttonPayload[valueKey] = pressed ? 1.0 : 0.0;
    _buttonPayload[pressedKey] = pressed;
    return sink.emit(type: type, data: _buttonPayload, active: pressed);
  }

  /// Forwards a normalized L2/R2 value in the 0..1 range.
  bool updateTrigger(VrGamepadButton trigger, double value) {
    if (trigger != VrGamepadButton.l2 && trigger != VrGamepadButton.r2) {
      throw ArgumentError.value(
        trigger,
        'trigger',
        'Only VrGamepadButton.l2 and VrGamepadButton.r2 are analog triggers.',
      );
    }

    final sink = _sink;
    if (sink == null) return false;

    final normalized = value.clamp(0.0, 1.0).toDouble();
    final pressed = normalized > triggerDeadzone;
    _triggerPayload[buttonKey] = trigger;
    _triggerPayload[valueKey] = normalized;
    _triggerPayload[pressedKey] = pressed;
    return sink.emit(
      type: VrInputType.trigger,
      data: _triggerPayload,
      active: pressed,
    );
  }

  /// Forwards normalized stick axes in the -1..1 range.
  ///
  /// Values inside the radial deadzone are emitted as `(0, 0)` with
  /// `active: false`, allowing locomotion consumers to stop immediately.
  bool updateStick(
    double x,
    double y, {
    VrGamepadStick stick = VrGamepadStick.left,
  }) {
    final sink = _sink;
    if (sink == null) return false;

    var normalizedX = x.clamp(-1.0, 1.0).toDouble();
    var normalizedY = y.clamp(-1.0, 1.0).toDouble();
    final active =
        normalizedX * normalizedX + normalizedY * normalizedY >
        stickDeadzone * stickDeadzone;
    if (!active) {
      normalizedX = 0.0;
      normalizedY = 0.0;
    }

    _stickPayload[stickKey] = stick;
    _stickPayload[xKey] = normalizedX;
    _stickPayload[yKey] = normalizedY;
    return sink.emit(
      type: VrInputType.navigate,
      data: _stickPayload,
      active: active,
    );
  }
}
