import 'vr_controller_protocol.dart';
import 'vr_transport.dart';

enum VrTransportConnectionState {
  disconnected,
  listening,
  connecting,
  authenticating,
  connected,
  error,
}

/// Extended transport used by paired smartphone controllers.
abstract interface class VrControllerTransport implements VrTransport {
  VrTransportConnectionState get state;
  Stream<VrTransportConnectionState> get onState;
  Stream<VrControllerProfile> get onProfile;
  Stream<VrRemotePoseFrame> get onPose;
  Stream<Duration> get onLatency;

  Future<void> sendProfile(VrControllerProfile profile);
  Future<void> sendPose(VrRemotePoseFrame frame);
  Future<Duration> measureLatency();
}
