import 'dart:async';

import 'package:flutter/foundation.dart';

/// Renderer lifecycle owned by one [VrSessionController].
///
/// Implementations decide which resources they own. A borrowed renderer must
/// not be disposed by [close]; release only listeners or resources this adapter
/// created. No Canvas, Flutter Scene or Thermion dependency is required here.
abstract interface class VrSessionAdapter {
  String get rendererId;
  FutureOr<void> start();
  FutureOr<void> pause();
  FutureOr<void> resume();
  FutureOr<void> close();
}

typedef VrSessionCallback = FutureOr<void> Function();

/// Marks a widget-owned renderer whose frame scheduling honors Flutter's
/// TickerMode. Use with VrSessionHost; the child widget retains disposal ownership.
/// This does not pause native rendering loops, timers, audio or sensor streams.
/// Those need explicit callbacks through [VrCallbackSessionAdapter].
class VrWidgetSessionAdapter implements VrSessionAdapter {
  const VrWidgetSessionAdapter({required this.rendererId});

  @override
  final String rendererId;
  @override
  void start() {}
  @override
  void pause() {}
  @override
  void resume() {}
  @override
  void close() {}
}

/// Adapts an existing renderer without transferring resource ownership.
///
/// The caller explicitly defines cleanup in [onClose]. The controller never
/// disposes a renderer independently of this callback.
class VrCallbackSessionAdapter implements VrSessionAdapter {
  const VrCallbackSessionAdapter({
    required this.rendererId,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onClose,
  });

  @override
  final String rendererId;
  final VrSessionCallback onStart;
  final VrSessionCallback onPause;
  final VrSessionCallback onResume;
  final VrSessionCallback onClose;

  @override
  FutureOr<void> start() => onStart();
  @override
  FutureOr<void> pause() => onPause();
  @override
  FutureOr<void> resume() => onResume();
  @override
  FutureOr<void> close() => onClose();
}

enum VrSessionStatus {
  idle,
  starting,
  running,
  pausing,
  paused,
  resuming,
  closing,
  closed,
  failed,
}

/// Serializes renderer operations independently of any state-management framework.
///
/// Starting is explicit: constructing a controller does not start a renderer. Failed
/// operations reject their returned Future and preserve [lastError]. Cleanup
/// remains available after failure. Closing is terminal, attempted once, and
/// waits for an in-flight operation before invoking the adapter's cleanup.
class VrSessionController {
  VrSessionController({required this.adapter});

  final VrSessionAdapter adapter;
  final _status = ValueNotifier<VrSessionStatus>(VrSessionStatus.idle);

  /// Read-only lifecycle notifications; transitions go through session methods.
  ValueListenable<VrSessionStatus> get status => _status;
  bool _disposeRequested = false;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closeRequested = false;
  Object? _lastError;
  StackTrace? _lastStackTrace;

  String get rendererId => adapter.rendererId;
  Object? get lastError => _lastError;
  StackTrace? get lastStackTrace => _lastStackTrace;

  /// True immediately when closing is requested. Await [closeSession] to wait
  /// for resource cleanup.
  bool get isClosed => _closeRequested;

  Future<void> start() => _enqueue(() async {
    if (_closeRequested || status.value != VrSessionStatus.idle) return;
    _status.value = VrSessionStatus.starting;
    await adapter.start();
    if (!_closeRequested) _status.value = VrSessionStatus.running;
  });

  Future<void> pause() => _enqueue(() async {
    if (_closeRequested || status.value != VrSessionStatus.running) return;
    _status.value = VrSessionStatus.pausing;
    await adapter.pause();
    if (!_closeRequested) _status.value = VrSessionStatus.paused;
  });

  /// Resumes only a paused session. An idle session must be started explicitly.
  Future<void> resume() => _enqueue(() async {
    if (_closeRequested || status.value != VrSessionStatus.paused) return;
    _status.value = VrSessionStatus.resuming;
    await adapter.resume();
    if (!_closeRequested) _status.value = VrSessionStatus.running;
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _tail.then((_) async {
      try {
        await operation();
      } catch (error, stack) {
        _lastError = error;
        _lastStackTrace = stack;
        if (!_closeRequested) _status.value = VrSessionStatus.failed;
        rethrow;
      }
    });
    // Recover the queue while preserving rejection on the caller's Future.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Idempotent, including when cleanup fails. A failed cleanup is observable
  /// through the returned Future and [lastError]; status still becomes closed.
  Future<void> closeSession() {
    if (_closeFuture != null) return _closeFuture!;
    _closeRequested = true;
    final result = _closeFuture = _enqueue(() async {
      _status.value = VrSessionStatus.closing;
      try {
        await adapter.close();
      } finally {
        _status.value = VrSessionStatus.closed;
      }
    });
    // Set the future before publishing, so a synchronous status listener calling
    // closeSession again observes the same terminal operation. Hosts can stop
    // frames immediately while initialization or another operation is pending.
    _status.value = VrSessionStatus.closing;
    return result;
  }

  /// Requests terminal cleanup and releases lifecycle listeners afterwards.
  /// Await [closeSession] when cleanup errors must be handled by the caller.
  /// [lastError] remains available even if cleanup fails during disposal.
  void dispose() {
    if (_disposeRequested) return;
    _disposeRequested = true;
    unawaited(
      closeSession().then<void>(
        (_) => _status.dispose(),
        onError: (Object _, StackTrace __) => _status.dispose(),
      ),
    );
  }
}
