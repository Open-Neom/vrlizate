import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

final class _FakeControllerTransport implements VrControllerTransport {
  final StreamController<VrTransportConnectionState> states =
      StreamController<VrTransportConnectionState>.broadcast(sync: true);
  final StreamController<VrControllerProfile> profiles =
      StreamController<VrControllerProfile>.broadcast(sync: true);
  final StreamController<VrRemotePoseFrame> poses =
      StreamController<VrRemotePoseFrame>.broadcast(sync: true);
  final StreamController<VrInputEvent> events =
      StreamController<VrInputEvent>.broadcast(sync: true);
  final StreamController<Duration> latencies =
      StreamController<Duration>.broadcast(sync: true);

  @override
  VrTransportConnectionState state = VrTransportConnectionState.disconnected;

  @override
  Stream<VrTransportConnectionState> get onState => states.stream;
  @override
  Stream<VrControllerProfile> get onProfile => profiles.stream;
  @override
  Stream<VrRemotePoseFrame> get onPose => poses.stream;
  @override
  Stream<VrInputEvent> get onEvent => events.stream;
  @override
  Stream<Duration> get onLatency => latencies.stream;

  void emitState(VrTransportConnectionState value) {
    state = value;
    states.add(value);
  }

  @override
  Future<void> connect(VrPairingPayload payload) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<Duration> measureLatency() async => Duration.zero;
  @override
  Future<void> sendEvent(VrInputEvent event) async {}
  @override
  Future<void> sendPose(VrRemotePoseFrame frame) async {}
  @override
  Future<void> sendProfile(VrControllerProfile profile) async {}

  Future<void> dispose() async {
    await states.close();
    await profiles.close();
    await poses.close();
    await events.close();
    await latencies.close();
  }
}

void main() {
  group('VrRemoteControllerSession', () {
    late _FakeControllerTransport transport;
    late VrInputArbiter arbiter;
    late CameraRig cameraRig;
    late Scene scene;
    late VrRemoteControllerSession session;
    late List<VrInputType> acceptedTypes;

    setUp(() {
      transport = _FakeControllerTransport();
      arbiter = VrInputArbiter(poolCapacity: 4);
      cameraRig = CameraRig();
      scene = Scene();
      acceptedTypes = <VrInputType>[];
      arbiter.addListener((event) => acceptedTypes.add(event.type));
      session = VrRemoteControllerSession(
        transport: transport,
        arbiter: arbiter,
        cameraRig: cameraRig,
        scene: scene,
      )..start();
    });

    tearDown(() async {
      await session.stop();
      arbiter.pool.assertNoLeaks();
      arbiter.dispose();
      await transport.dispose();
    });

    test('builds and anchors a visual phone from the remote profile', () {
      transport.emitState(VrTransportConnectionState.connected);
      transport.profiles.add(_profile());

      expect(session.avatar, isNotNull);
      expect(scene.root.findChild('remote-controller-child-phone'), isNotNull);
      expect(session.controllerState!.connected, isTrue);

      scene.update(1 / 60);
      final position = session.avatar!.transform.position;
      expect(position.x, closeTo(0.25, 1e-7));
      expect(position.y, closeTo(-0.24, 1e-7));
      expect(position.z, closeTo(-0.55, 1e-7));
    });

    test('updates orientation, buttons, range, and pointer input', () {
      transport.emitState(VrTransportConnectionState.connected);
      transport.profiles.add(_profile());
      final orientation = Quaternion.axisAngle(Vector3(0, 1, 0), 0.5);

      transport.poses.add(
        VrRemotePoseFrame(
          sequence: 1,
          senderTimestampMicroseconds: 100,
          orientation: orientation,
          buttonsBitset: 5,
          rangeMeters: 0.7,
          rangeSource: VrRangeSource.bluetoothRssi,
          rangeConfidence: 0.3,
        ),
      );

      expect(session.lastSequence, 1);
      expect(session.avatar!.isControlActive('select'), isTrue);
      expect(session.avatar!.isControlActive('back'), isFalse);
      expect(session.avatar!.isControlActive('trigger'), isTrue);
      expect(session.avatar!.rangeMeters, 0.7);
      expect(session.controllerState!.primaryButtonPressed, isTrue);
      expect(session.controllerState!.triggerPressed, isTrue);
      expect(acceptedTypes, contains(VrInputType.pointerMove));
    });

    test('drops reordered frames and hides the avatar on disconnect', () {
      transport.emitState(VrTransportConnectionState.connected);
      transport.profiles.add(_profile());
      transport.poses.add(_frame(8, 0.8));
      final acceptedAfterNew = acceptedTypes.length;

      transport.poses.add(_frame(7, -0.8));

      expect(session.lastSequence, 8);
      expect(acceptedTypes, hasLength(acceptedAfterNew));

      transport.emitState(VrTransportConnectionState.disconnected);
      expect(session.avatar!.visible, isFalse);
      expect(session.controllerState!.connected, isFalse);
    });

    test('routes discrete remote events through the arbiter', () {
      transport.profiles.add(_profile());
      transport.events.add(
        VrInputEvent(
          type: VrInputType.trigger,
          source: VrInputSource.remotePhone,
          active: true,
        ),
      );

      expect(acceptedTypes, contains(VrInputType.trigger));
      expect(session.controllerState!.triggerPressed, isTrue);
    });

    test('turns remote touch into navigation and releases it', () {
      transport.profiles.add(_profile());
      transport.poses.add(
        VrRemotePoseFrame(
          sequence: 1,
          senderTimestampMicroseconds: 100,
          orientation: Quaternion.identity(),
          touchX: 1,
          touchY: 0.5,
        ),
      );

      expect(acceptedTypes, contains(VrInputType.navigate));
      expect(session.controllerState!.thumbstick.x, closeTo(1, 1e-8));
      expect(session.controllerState!.thumbstick.y, closeTo(0, 1e-8));
      expect(session.touchpadDriver.isActive, isTrue);

      transport.poses.add(
        VrRemotePoseFrame(
          sequence: 2,
          senderTimestampMicroseconds: 200,
          orientation: Quaternion.identity(),
        ),
      );
      expect(session.touchpadDriver.isActive, isFalse);
      expect(session.controllerState!.thumbstick, Vector2.zero());
    });

    test('emits trigger edges carried by pose frames', () {
      transport.profiles.add(_profile());
      transport.poses.add(
        VrRemotePoseFrame(
          sequence: 1,
          senderTimestampMicroseconds: 100,
          orientation: Quaternion.identity(),
          buttonsBitset: 4,
        ),
      );
      transport.poses.add(
        VrRemotePoseFrame(
          sequence: 2,
          senderTimestampMicroseconds: 200,
          orientation: Quaternion.identity(),
          buttonsBitset: 0,
        ),
      );

      expect(
        acceptedTypes.where((type) => type == VrInputType.trigger),
        hasLength(2),
      );
      expect(session.controllerState!.triggerPressed, isFalse);
    });

    test('applies measured latency to render-time pose prediction', () async {
      await session.stop();
      var now = 1000000;
      final predictor = VrRemotePosePredictor(
        renderLead: Duration.zero,
        clock: () => now,
      );
      session = VrRemoteControllerSession(
        transport: transport,
        arbiter: arbiter,
        cameraRig: cameraRig,
        scene: scene,
        posePredictor: predictor,
      )..start();
      transport.profiles.add(_profile());
      transport.latencies.add(const Duration(milliseconds: 20));
      transport.poses.add(
        VrRemotePoseFrame(
          sequence: 1,
          senderTimestampMicroseconds: 100,
          orientation: Quaternion.identity(),
          angularVelocity: Vector3(0, 1, 0),
        ),
      );

      now += 10000;
      expect(session.updatePosePrediction(), isTrue);
      expect(predictor.lastPredictionHorizon, const Duration(milliseconds: 20));
      expect(session.pointerDriver.orientation.y, closeTo(0.01, 1e-4));
    });
  });
}

VrRemotePoseFrame _frame(int sequence, double yaw) => VrRemotePoseFrame(
  sequence: sequence,
  senderTimestampMicroseconds: sequence * 100,
  orientation: Quaternion.axisAngle(Vector3(0, 1, 0), yaw),
);

VrControllerProfile _profile() => VrControllerProfile(
  deviceId: 'child-phone',
  deviceName: 'Controller phone',
  handedness: VrControllerHandedness.right,
  widthMeters: 0.072,
  heightMeters: 0.155,
  controls: <VrControlDescriptor>[
    VrControlDescriptor(
      id: 'select',
      label: 'A',
      kind: VrControlKind.button,
      x: 0.75,
      y: 0.75,
    ),
    VrControlDescriptor(
      id: 'back',
      label: 'B',
      kind: VrControlKind.button,
      x: 0.25,
      y: 0.75,
    ),
    VrControlDescriptor(
      id: 'trigger',
      label: 'T',
      kind: VrControlKind.trigger,
      x: 0.5,
      y: 0.25,
    ),
  ],
);
