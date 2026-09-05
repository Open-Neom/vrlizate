import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('VrLocalSocketTransport', () {
    late VrLocalSocketTransport visor;
    late VrLocalSocketTransport controller;

    setUp(() {
      visor = VrLocalSocketTransport();
      controller = VrLocalSocketTransport();
    });

    tearDown(() async {
      await controller.dispose();
      await visor.dispose();
    });

    test('authenticates and exchanges profile, pose, and input', () async {
      final invitation = await visor.listen(
        advertisedHost: '127.0.0.1',
        bindHost: '127.0.0.1',
        sessionToken: 'one-time-secret',
        deviceName: 'Visor',
      );

      await controller.connect(invitation);
      expect(controller.state, VrTransportConnectionState.connected);
      expect(visor.state, VrTransportConnectionState.connected);

      final profile = _profile();
      final profileReceived = visor.onProfile.first;
      await controller.sendProfile(profile);
      expect(await profileReceived, profile);

      final frame = VrRemotePoseFrame(
        sequence: 9,
        senderTimestampMicroseconds: 500,
        orientation: Quaternion.axisAngle(Vector3(0, 1, 0), 0.4),
        angularVelocity: Vector3(0, 0.2, 0),
        buttonsBitset: 1,
      );
      final poseReceived = visor.onPose.first;
      await controller.sendPose(frame);
      expect(await poseReceived, frame);

      final eventReceived = visor.onEvent.first;
      final pool = VrInputEventPool(capacity: 1);
      final orientation = Quaternion.identity();
      final event = pool.acquire(
        type: VrInputType.pointerMove,
        source: VrInputSource.remotePhone,
        timestampMicrosecondsSinceEpoch: 999,
        data: <String, dynamic>{
          'orientation': orientation,
          'forward': Vector3(0, 0, -1),
        },
      );
      final send = controller.sendEvent(event);
      pool.release(event);
      orientation.setValues(1, 0, 0, 0);
      await send;

      final decoded = await eventReceived;
      expect(decoded.type, VrInputType.pointerMove);
      expect(decoded.timestampMicrosecondsSinceEpoch, 999);
      expect(decoded.data!['orientation'], Quaternion.identity());
      expect(decoded.data!['forward'], Vector3(0, 0, -1));
      pool.assertNoLeaks();

      final latency = await controller.measureLatency();
      expect(latency, greaterThanOrEqualTo(Duration.zero));
    });

    test('rejects an invalid pairing token and remains available', () async {
      final invitation = await visor.listen(
        advertisedHost: '127.0.0.1',
        bindHost: '127.0.0.1',
        sessionToken: 'correct-token',
      );
      final invalid = VrPairingPayload(
        host: invitation.host,
        port: invitation.port,
        sessionToken: 'wrong-token',
        role: VrDeviceRole.parent,
        transportType: VrTransportType.localSocket,
      );

      await expectLater(
        controller.connect(invalid),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('authentication_failed'),
          ),
        ),
      );

      await _waitFor(() => visor.state == VrTransportConnectionState.listening);
      expect(visor.isListening, isTrue);
      expect(visor.isConnected, isFalse);
    });

    test('returns to listening after the child disconnects', () async {
      final invitation = await visor.listen(
        advertisedHost: '127.0.0.1',
        bindHost: '127.0.0.1',
        sessionToken: 'token',
      );
      await controller.connect(invitation);

      await controller.disconnect();
      await _waitFor(() => visor.state == VrTransportConnectionState.listening);

      expect(visor.isListening, isTrue);
      expect(visor.isConnected, isFalse);
    });

    test('drives a visual controller end to end from child IMU', () async {
      final invitation = await visor.listen(
        advertisedHost: '127.0.0.1',
        bindHost: '127.0.0.1',
        sessionToken: 'e2e-token',
      );
      await controller.connect(invitation);

      final arbiter = VrInputArbiter(poolCapacity: 4);
      final cameraRig = CameraRig();
      final scene = Scene();
      final session = VrRemoteControllerSession(
        transport: visor,
        arbiter: arbiter,
        cameraRig: cameraRig,
        scene: scene,
      )..start();
      final gyroscope = StreamController<GyroscopeEvent>.broadcast(sync: true);
      final accelerometer = StreamController<AccelerometerEvent>.broadcast(
        sync: true,
      );
      final imu = VrRemoteImuController(
        transport: controller,
        profile: _profile(),
        screenOrientation: VrImuScreenOrientation.portraitUp,
        minimumSendInterval: Duration.zero,
        gyroscopeStreamOverride: gyroscope.stream,
        accelerometerStreamOverride: accelerometer.stream,
      );

      try {
        await imu.start();
        await _waitFor(() => session.avatar != null);
        imu.setButtonsBitset(1);
        await imu.flush();
        await _waitFor(() => session.lastSequence >= 0);
        scene.update(1 / 60);

        expect(session.profile, _profile());
        expect(session.avatar!.isControlActive('select'), isTrue);
        expect(session.avatar!.transform.position.z, closeTo(-0.55, 1e-7));
        expect(session.controllerState!.connected, isTrue);
      } finally {
        await imu.stop();
        await gyroscope.close();
        await accelerometer.close();
        await session.stop();
        arbiter.pool.assertNoLeaks();
        arbiter.dispose();
      }
    });
  });
}

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
  ],
);

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
