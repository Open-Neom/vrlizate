import '../core/engine/vr_engine.dart';

import 'vr_session.dart';

/// Drives a Canvas engine's frame loop. Sensors/resources remain with its owner.
///
/// Borrowing is the default. Set [ownsEngine] only when transferring exclusive
/// disposal ownership to this adapter; never transfer an engine owned by another component.
class VREngineSessionAdapter implements VrSessionAdapter {
  VREngineSessionAdapter({required this.engine, this.ownsEngine = false});

  final VREngine engine;
  final bool ownsEngine;
  bool _closed = false;
  bool _startedLoop = false;

  @override
  String get rendererId => 'vrlizate.canvas';

  @override
  void start() {
    if (_closed) return;
    if (!engine.isRunning) {
      _startedLoop = true;
      engine.start();
    }
  }

  @override
  void pause() {
    if (!_closed) engine.stop();
  }

  @override
  void resume() => start();

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    if (ownsEngine) {
      engine.dispose();
    } else if (_startedLoop) {
      engine.stop();
    }
  }
}
