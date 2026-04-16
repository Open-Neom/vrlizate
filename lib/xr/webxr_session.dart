/// WebXR session management abstraction.
/// Provides the interface for future WebXR integration
/// when Flutter web supports immersive sessions.
///
/// Based on three_js XR patterns.
library;

enum XRSessionMode {
  immersiveVr('immersive-vr'),
  immersiveAr('immersive-ar'),
  inline('inline');

  const XRSessionMode(this.value);
  final String value;
}

enum XRReferenceSpaceType {
  viewer('viewer'),
  local('local'),
  localFloor('local-floor'),
  boundedFloor('bounded-floor'),
  unbounded('unbounded');

  const XRReferenceSpaceType(this.value);
  final String value;
}

/// Abstract XR session for future WebXR/AndroidXR integration.
abstract class XRSession {
  /// Session mode.
  XRSessionMode get mode;

  /// Whether the session is active.
  bool get isActive;

  /// Starts an XR session.
  Future<bool> requestSession(
    XRSessionMode mode, {
    List<String> requiredFeatures = const [],
    List<String> optionalFeatures = const [],
  });

  /// Ends the current XR session.
  Future<void> endSession();

  /// Gets the reference space for tracking.
  Future<void> requestReferenceSpace(XRReferenceSpaceType type);

  /// Called each XR frame with viewer pose data.
  void onXRFrame(double timestamp, dynamic frame);

  /// Foveation level (0-1, 0 = best quality, 1 = best performance).
  void setFoveation(double level);
}

/// Stub implementation for platforms without XR support.
class XRSessionStub implements XRSession {
  @override
  XRSessionMode get mode => XRSessionMode.inline;

  @override
  bool get isActive => false;

  @override
  Future<bool> requestSession(
    XRSessionMode mode, {
    List<String> requiredFeatures = const [],
    List<String> optionalFeatures = const [],
  }) async => false;

  @override
  Future<void> endSession() async {}

  @override
  Future<void> requestReferenceSpace(XRReferenceSpaceType type) async {}

  @override
  void onXRFrame(double timestamp, dynamic frame) {}

  @override
  void setFoveation(double level) {}
}
