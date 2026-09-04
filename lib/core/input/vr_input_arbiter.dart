import 'vr_input_event_bus.dart';

/// Input priority used to resolve simultaneous multimodal interactions.
enum VrInputPriority { base, medium, maximum }

/// Synchronous listener used by the allocation-free arbitration path.
///
/// The event is borrowed from a pool and is only valid for the duration of
/// the callback. Copy the values you need; never retain the event itself.
typedef VrInputListener = void Function(VrInputEvent event);

/// Monotonic time source in microseconds.
typedef VrInputClock = int Function();

/// Sink passed to a [VrInputDriver] when it is attached to an arbiter.
///
/// A high-frequency driver should acquire one event, submit it, and release it
/// in a `finally` block. [emit] is a convenient acquire/submit/release wrapper
/// for discrete events.
abstract interface class VrInputSink {
  VrInputEvent acquire({
    required VrInputType type,
    String? targetId,
    Map<String, dynamic>? data,
    bool active = true,
  });

  bool submit(VrInputEvent event);

  void release(VrInputEvent event);

  bool emit({
    required VrInputType type,
    String? targetId,
    Map<String, dynamic>? data,
    bool active = true,
  });
}

/// Extension point for gamepads, phones, vision systems, and custom sensors.
///
/// Drivers own their hardware subscriptions. [attach] receives a sink bound
/// to [source], and [detach] must cancel subscriptions and release every event
/// still checked out from the sink.
abstract interface class VrInputDriver {
  VrInputSource get source;

  void attach(VrInputSink sink);

  void detach();
}

/// Optional per-driver priority override.
///
/// Most drivers inherit the stable priority of their [VrInputDriver.source].
/// A specialized driver can implement this interface when the same hardware
/// source exposes interaction modes with different arbitration semantics.
abstract interface class VrInputPrioritizedDriver {
  VrInputPriority get priority;
}

/// Fixed-capacity pool for [VrInputEvent] instances.
///
/// The pool preallocates all events. Exhaustion throws instead of allocating a
/// fallback object, preserving deterministic behavior on low-memory phones.
class VrInputEventPool {
  late final List<_PooledVrInputEvent> _events;
  late final List<int> _freeSlots;

  int _inUseCount = 0;
  int _peakInUse = 0;
  int _totalAcquisitions = 0;

  VrInputEventPool({int capacity = 64}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive.');
    }

    _events = List<_PooledVrInputEvent>.generate(
      capacity,
      (slot) => _PooledVrInputEvent(this, slot),
      growable: false,
    );
    _freeSlots = List<int>.generate(
      capacity,
      (index) => capacity - index - 1,
      growable: true,
    );
  }

  int get capacity => _events.length;
  int get availableCount => _freeSlots.length;
  int get inUseCount => _inUseCount;
  int get peakInUse => _peakInUse;
  int get totalAcquisitions => _totalAcquisitions;

  VrInputEvent acquire({
    required VrInputType type,
    required VrInputSource source,
    required int timestampMicrosecondsSinceEpoch,
    String? targetId,
    Map<String, dynamic>? data,
    bool active = true,
  }) {
    if (_freeSlots.isEmpty) {
      throw StateError(
        'VrInputEventPool exhausted ($capacity events are already in use).',
      );
    }

    final slot = _freeSlots.removeLast();
    final event = _events[slot];
    event._checkedOut = true;
    event.resetForReuse(
      type: type,
      source: source,
      targetId: targetId,
      data: data,
      active: active,
      timestampMicrosecondsSinceEpoch: timestampMicrosecondsSinceEpoch,
    );

    _inUseCount++;
    _totalAcquisitions++;
    if (_inUseCount > _peakInUse) _peakInUse = _inUseCount;
    return event;
  }

  void release(VrInputEvent event) {
    if (event is! _PooledVrInputEvent || !identical(event._owner, this)) {
      throw ArgumentError.value(
        event,
        'event',
        'The event does not belong to this pool.',
      );
    }
    if (!event._checkedOut) {
      throw StateError('VrInputEvent was released more than once.');
    }

    event.clearForReuse();
    event._checkedOut = false;
    _freeSlots.add(event._slot);
    _inUseCount--;
  }

  /// Throws when a driver forgot to return one or more events.
  void assertNoLeaks() {
    if (_inUseCount != 0) {
      throw StateError(
        'VrInputEventPool leak: $_inUseCount of $capacity events not released.',
      );
    }
  }
}

final class _PooledVrInputEvent extends VrInputEvent {
  final VrInputEventPool _owner;
  final int _slot;
  bool _checkedOut = false;

  _PooledVrInputEvent(this._owner, this._slot)
    : super(type: VrInputType.hover, source: VrInputSource.gaze);
}

/// Resolves input conflicts without allocating in the per-frame event path.
///
/// Priorities are fixed and predictable:
///
/// 1. [VrInputSource.remotePhone] and [VrInputSource.touch]
/// 2. Temple taps, gamepads, hands, voice, sonar, and external peripherals
/// 3. [VrInputSource.gaze]
///
/// An active source suppresses actionable lower-priority events until
/// [suppressionWindow] has elapsed. Gaze hover remains visible so a reticle can
/// continue tracking; gaze select (the dwell auto-click) is suppressed.
class VrInputArbiter {
  final Duration suppressionWindow;
  final VrInputEventPool pool;
  final VrInputClock _clock;

  final List<VrInputListener> _listeners = <VrInputListener>[];
  final List<_DriverRegistration> _drivers = <_DriverRegistration>[];
  final List<int> _lastActiveAt = List<int>.filled(
    VrInputPriority.values.length,
    -0x3FFFFFFFFFFFFFFF,
  );

  int _dispatchDepth = 0;
  bool _disposed = false;

  VrInputArbiter({
    this.suppressionWindow = const Duration(milliseconds: 400),
    int poolCapacity = 64,
    VrInputClock? clock,
  }) : pool = VrInputEventPool(capacity: poolCapacity),
       _clock = clock ?? _EpochMonotonicClock().now {
    if (suppressionWindow.isNegative) {
      throw ArgumentError.value(
        suppressionWindow,
        'suppressionWindow',
        'Must not be negative.',
      );
    }
  }

  /// Maps a source to the stable VRlizate priority hierarchy.
  static VrInputPriority priorityOf(VrInputSource source) {
    return switch (source) {
      VrInputSource.remotePhone ||
      VrInputSource.touch => VrInputPriority.maximum,
      VrInputSource.gaze => VrInputPriority.base,
      VrInputSource.templeTap ||
      VrInputSource.voice ||
      VrInputSource.sonar ||
      VrInputSource.cameraHand ||
      VrInputSource.gamepad ||
      VrInputSource.externalPeripheral => VrInputPriority.medium,
    };
  }

  /// Whether a gaze dwell selection would be suppressed right now.
  bool get isGazeSuppressed =>
      _hasActiveHigherPriority(VrInputPriority.base, _clock());

  void addListener(VrInputListener listener) {
    _ensureAlive();
    _ensureListenersCanChange();
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  bool removeListener(VrInputListener listener) {
    _ensureAlive();
    _ensureListenersCanChange();
    return _listeners.remove(listener);
  }

  VrInputEvent acquire({
    required VrInputType type,
    required VrInputSource source,
    String? targetId,
    Map<String, dynamic>? data,
    bool active = true,
  }) {
    _ensureAlive();
    return pool.acquire(
      type: type,
      source: source,
      targetId: targetId,
      data: data,
      active: active,
      timestampMicrosecondsSinceEpoch: _clock(),
    );
  }

  /// Submits an event and returns whether it reached listeners.
  ///
  /// The caller still owns the event and must release pooled events even when
  /// this method returns `false` or a listener throws.
  bool submit(VrInputEvent event) {
    return _submit(event, priorityOf(event.source));
  }

  bool _submit(VrInputEvent event, VrInputPriority priority) {
    _ensureAlive();
    final now = _clock();

    if (event.active && priority != VrInputPriority.base) {
      _lastActiveAt[priority.index] = now;
    }

    if (event.type != VrInputType.hover &&
        _hasActiveHigherPriority(priority, now)) {
      return false;
    }

    _dispatchDepth++;
    try {
      for (var i = 0; i < _listeners.length; i++) {
        _listeners[i](event);
      }
    } finally {
      _dispatchDepth--;
    }
    return true;
  }

  void release(VrInputEvent event) => pool.release(event);

  /// Allocation-free convenience after the pool has been initialized.
  bool emit({
    required VrInputType type,
    required VrInputSource source,
    String? targetId,
    Map<String, dynamic>? data,
    bool active = true,
  }) {
    final event = acquire(
      type: type,
      source: source,
      targetId: targetId,
      data: data,
      active: active,
    );
    try {
      return submit(event);
    } finally {
      release(event);
    }
  }

  /// Attaches a community driver and binds its sink to [VrInputDriver.source].
  void attachDriver(VrInputDriver driver) {
    _ensureAlive();
    for (final registration in _drivers) {
      if (identical(registration.driver, driver)) {
        throw StateError('VrInputDriver is already attached.');
      }
    }

    final registration = _DriverRegistration(
      driver,
      _BoundInputSink(
        this,
        driver.source,
        driver is VrInputPrioritizedDriver
            ? (driver as VrInputPrioritizedDriver).priority
            : priorityOf(driver.source),
      ),
    );
    _drivers.add(registration);
    try {
      driver.attach(registration.sink);
    } catch (_) {
      registration.sink._attached = false;
      _drivers.removeLast();
      rethrow;
    }
  }

  bool detachDriver(VrInputDriver driver) {
    _ensureAlive();
    for (var i = 0; i < _drivers.length; i++) {
      final registration = _drivers[i];
      if (!identical(registration.driver, driver)) continue;
      driver.detach();
      registration.sink._attached = false;
      _drivers.removeAt(i);
      return true;
    }
    return false;
  }

  void dispose() {
    if (_disposed) return;
    for (var i = _drivers.length - 1; i >= 0; i--) {
      final registration = _drivers[i];
      registration.driver.detach();
      registration.sink._attached = false;
    }
    _drivers.clear();
    _listeners.clear();
    _disposed = true;
  }

  bool _hasActiveHigherPriority(VrInputPriority priority, int now) {
    final window = suppressionWindow.inMicroseconds;
    for (var i = priority.index + 1; i < _lastActiveAt.length; i++) {
      final elapsed = now - _lastActiveAt[i];
      if (elapsed >= 0 && elapsed < window) return true;
    }
    return false;
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('VrInputArbiter has been disposed.');
  }

  void _ensureListenersCanChange() {
    if (_dispatchDepth != 0) {
      throw StateError('Listeners cannot change during event dispatch.');
    }
  }
}

final class _DriverRegistration {
  final VrInputDriver driver;
  final _BoundInputSink sink;

  const _DriverRegistration(this.driver, this.sink);
}

final class _BoundInputSink implements VrInputSink {
  final VrInputArbiter _arbiter;
  final VrInputSource _source;
  final VrInputPriority _priority;
  bool _attached = true;

  _BoundInputSink(this._arbiter, this._source, this._priority);

  @override
  VrInputEvent acquire({
    required VrInputType type,
    String? targetId,
    Map<String, dynamic>? data,
    bool active = true,
  }) {
    _ensureAttached();
    return _arbiter.acquire(
      type: type,
      source: _source,
      targetId: targetId,
      data: data,
      active: active,
    );
  }

  @override
  bool submit(VrInputEvent event) {
    _ensureAttached();
    if (event.source != _source) {
      throw ArgumentError.value(
        event.source,
        'event.source',
        'Driver sink is bound to $_source.',
      );
    }
    return _arbiter._submit(event, _priority);
  }

  @override
  void release(VrInputEvent event) => _arbiter.release(event);

  @override
  bool emit({
    required VrInputType type,
    String? targetId,
    Map<String, dynamic>? data,
    bool active = true,
  }) {
    final event = acquire(
      type: type,
      targetId: targetId,
      data: data,
      active: active,
    );
    try {
      return submit(event);
    } finally {
      release(event);
    }
  }

  void _ensureAttached() {
    if (!_attached) throw StateError('VrInputDriver is detached.');
  }
}

final class _EpochMonotonicClock {
  final int _epochStart = DateTime.now().microsecondsSinceEpoch;
  final Stopwatch _stopwatch = Stopwatch()..start();

  int now() => _epochStart + _stopwatch.elapsedMicroseconds;
}
