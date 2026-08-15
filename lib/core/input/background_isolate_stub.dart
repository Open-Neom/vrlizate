/// No-op stub for platforms without `dart:isolate` (web / WASM).
///
/// Mirrors the API of `background_isolate_io.dart`. The entry-point symbols
/// exist so conditional-export consumers compile, but they are never called:
/// callers disable background processing when isolates are unavailable.
library;

/// Generic handle to a background worker (stub: does nothing).
class BackgroundIsolate {
  BackgroundIsolate._();

  /// Opens the message channel (stub: no-op).
  static BackgroundIsolate create() => BackgroundIsolate._();

  /// Messages received from the worker (stub: empty stream).
  Stream<dynamic> get messages => const Stream<dynamic>.empty();

  /// Spawns the worker (stub: completes immediately).
  Future<void> start(void Function(dynamic) entryPoint) async {}

  /// Releases resources (stub: no-op).
  void dispose() {}
}

/// Head-tracking sensor fusion entry point (stub, never called).
void headTrackingFusionEntry(dynamic mainSendPort) {
  throw UnsupportedError('Isolates are not supported on this platform');
}

/// WiFi CSI processing entry point (stub, never called).
void wifiCsiProcessingEntry(dynamic mainSendPort) {
  throw UnsupportedError('Isolates are not supported on this platform');
}
