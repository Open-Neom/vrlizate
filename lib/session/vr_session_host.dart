import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'vr_session.dart';

typedef VrSessionWidgetBuilder =
    Widget Function(
      BuildContext context,
      VrSessionController controller,
      bool active,
    );

/// Renderer session boundary for a renderer page.
///
/// The host pauses on background, covered routes and disabled ancestor tickers.
/// [builder]'s active flag reflects visibility and excludes paused, failed and
/// closing sessions. Initialization can build an active renderer widget; inspect
/// controller.status for asynchronous readiness. The adapter must remain stable for this
/// widget's lifetime; use a different key when changing the renderer.
class VrSessionHost extends StatefulWidget {
  const VrSessionHost({
    super.key,
    required this.adapter,
    required this.builder,
    this.onError,
    this.onCreated,
    this.onDisposed,
  });

  /// Hooks for integrations such as dependency injection. The host owns the
  /// controller; integrations may borrow it but must not dispose its notifier.
  final ValueChanged<VrSessionController>? onCreated;
  final ValueChanged<VrSessionController>? onDisposed;

  final VrSessionAdapter adapter;
  final VrSessionWidgetBuilder builder;
  final void Function(Object error, StackTrace stack)? onError;

  static VrSessionController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_VrSessionScope>()?.controller;

  static VrSessionController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller == null) {
      throw FlutterError('VrSessionHost.of requires a VrSessionHost ancestor.');
    }
    return controller;
  }

  @override
  State<VrSessionHost> createState() => _VrSessionHostState();
}

class _VrSessionHostState extends State<VrSessionHost>
    with WidgetsBindingObserver {
  late final VrSessionController _controller;
  AppLifecycleState? _lifecycle;
  bool _routeCurrent = true;
  bool _tickersEnabled = true;
  bool _visible = false;
  bool _reconciling = false;
  bool _statusRebuildScheduled = false;
  bool _disposing = false;

  bool get _active {
    if (!_visible || _controller.isClosed) return false;
    return switch (_controller.status.value) {
      VrSessionStatus.pausing ||
      VrSessionStatus.paused ||
      VrSessionStatus.failed ||
      VrSessionStatus.closing ||
      VrSessionStatus.closed => false,
      _ => true,
    };
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _controller = VrSessionController(adapter: widget.adapter);
    _controller.status.addListener(_onStatusChanged);
    widget.onCreated?.call(_controller);
  }

  void _onStatusChanged() {
    if (!mounted || _disposing || _statusRebuildScheduled) return;
    // The public controller can be closed by descendants, including during a
    // build. Deferring only during frame callbacks avoids setState-during-build
    // and does not require another lifecycle event to stop a failed renderer.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _statusRebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _statusRebuildScheduled = false;
        if (mounted && !_disposing) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  bool get _applicationActive {
    if (_lifecycle == null || _lifecycle == AppLifecycleState.resumed) {
      return true;
    }
    if (_lifecycle != AppLifecycleState.inactive) return false;
    // Desktop windows may remain visible while focus is on another window.
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    _synchronize();
  }

  @override
  void didUpdateWidget(VrSessionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.adapter, widget.adapter)) {
      throw FlutterError(
        'VrSessionHost.adapter changed without a new key. Keep the adapter in '
        'State or provide a new key for a new renderer session.',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    _lifecycle = state;
    setState(_synchronize);
  }

  void _synchronize() {
    _visible = _applicationActive && _routeCurrent && _tickersEnabled;
    if (_reconciling) return;
    _reconciling = true;
    // Coalesce visibility changes before starting a renderer, and re-read
    // visibility after every asynchronous operation.
    _observe(
      Future<void>.microtask(() async {
        try {
          while (mounted && !_controller.isClosed) {
            final status = _controller.status.value;
            if (_visible && status == VrSessionStatus.idle) {
              await _controller.start();
            } else if (_visible && status == VrSessionStatus.paused) {
              await _controller.resume();
            } else if (!_visible && status == VrSessionStatus.running) {
              await _controller.pause();
            } else {
              break;
            }
          }
        } finally {
          _reconciling = false;
        }
      }),
    );
  }

  void _observe(Future<void> operation) {
    unawaited(
      operation.catchError((Object error, StackTrace stack) {
        final handler = widget.onError;
        if (handler != null) {
          handler(error, stack);
        } else {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'vrlizate',
              context: ErrorDescription(
                'while changing a VR session lifecycle',
              ),
            ),
          );
        }
      }),
    );
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _controller.status.removeListener(_onStatusChanged);
    _visible = false;
    // close is the terminal adapter operation; the adapter owns stopping and
    // cleanup. Calling pause separately could race with resource destruction.
    _observe(_controller.closeSession());
    try {
      widget.onDisposed?.call(_controller);
    } finally {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _VrSessionScope(
    controller: _controller,
    child: TickerMode(
      enabled: _active,
      child: Builder(
        builder: (context) => widget.builder(context, _controller, _active),
      ),
    ),
  );
}

class _VrSessionScope extends InheritedWidget {
  const _VrSessionScope({required this.controller, required super.child});

  final VrSessionController controller;

  @override
  bool updateShouldNotify(_VrSessionScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}
