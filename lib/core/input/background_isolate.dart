/// Cross-platform background isolate support.
///
/// The real implementation uses `dart:isolate` (VM / native). On platforms
/// without isolate support (web, WASM) a no-op stub is exported instead,
/// keeping the package WASM-compatible. Callers guard with `kIsWeb` /
/// capability flags, so the stub is never exercised in practice.
library;

export 'background_isolate_stub.dart'
    if (dart.library.isolate) 'background_isolate_io.dart';
