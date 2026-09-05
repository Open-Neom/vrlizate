import 'dart:async';

import '../input/vr_input_event_bus.dart';
import 'vr_controller_protocol.dart';
import 'vr_controller_transport.dart';
import 'vr_pairing_payload.dart';

/// Unsupported-platform placeholder. Use WebRTC/WebSocket on web builds.
class VrLocalSocketTransport implements VrControllerTransport {
  static const bool isSupported = false;

  Never _unsupported() => throw UnsupportedError(
    'VrLocalSocketTransport requires a dart:io platform.',
  );

  @override
  VrTransportConnectionState get state =>
      VrTransportConnectionState.disconnected;

  bool get isListening => false;
  bool get isConnected => false;

  @override
  Stream<VrTransportConnectionState> get onState => const Stream.empty();

  @override
  Stream<VrControllerProfile> get onProfile => const Stream.empty();

  @override
  Stream<VrRemotePoseFrame> get onPose => const Stream.empty();

  @override
  Stream<VrInputEvent> get onEvent => const Stream.empty();

  @override
  Stream<Duration> get onLatency => const Stream.empty();

  Future<VrPairingPayload> listen({
    required String advertisedHost,
    String bindHost = '0.0.0.0',
    int port = 0,
    required String sessionToken,
    String? deviceName,
  }) async => _unsupported();

  @override
  Future<void> connect(VrPairingPayload payload) async => _unsupported();

  @override
  Future<void> sendProfile(VrControllerProfile profile) async => _unsupported();

  @override
  Future<void> sendPose(VrRemotePoseFrame frame) async => _unsupported();

  @override
  Future<void> sendEvent(VrInputEvent event) async => _unsupported();

  @override
  Future<Duration> measureLatency() async => _unsupported();

  @override
  Future<void> disconnect() async => _unsupported();

  Future<void> dispose() async => _unsupported();
}
