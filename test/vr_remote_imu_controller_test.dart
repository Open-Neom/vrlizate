import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vrlizate/vrlizate.dart';

final class _CapturingTransport implements VrControllerTransport {
  final List<VrControllerProfile> sentProfiles = <VrControllerProfile>[];
  final List<VrRemotePoseFrame> sentFrames = <VrRemotePoseFrame>[];

  @override
  VrTransportConnectionState state = VrTransportConnectionState.connected;
  @override
  Stream<VrInputEvent> get onEvent => const Stream<VrInputEvent>.empty();
  @override
  Stream<Duration> get onLatency => const Stream<Duration>.empty();
  @override
  Stream<VrRemotePoseFrame> get onPose =>
      const Stream<VrRemotePoseFrame>.empty();
  @override
  Stream<VrControllerProfile> get onProfile =>
      const Stream<VrControllerProfile>.empty();
  @override
  Stream<VrTransportConnectionState> get onState =>
      const Stream<VrTransportConnectionState>.empty();

  @override
  Future<void> connect(VrPairingPayload payload) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<Duration> measureLatency() async => Duration.zero;
  @override
  Future<void> sendEvent(VrInputEvent event) async {}
  @override
  Future<void> sendPose(VrRemotePoseFrame frame) async {
    sentFrames.add(frame);
  }

  @override
  Future<void> sendProfile(VrControllerProfile profile) async {
    sentProfiles.add(profile);
  }
}

void main() {
  group('VrRemoteImuController', () {
    late _CapturingTransport transport;
    late StreamController<GyroscopeEvent> gyroscope;
    late StreamController<AccelerometerEvent> accelerometer;
    late VrRemoteImuController controller;

    setUp(() {
      transport = _CapturingTransport();
      gyroscope = StreamController<GyroscopeEvent>.broadcast(sync: true);
      accelerometer = StreamController<AccelerometerEvent>.broadcast(
        sync: true,
      );
      controller = VrRemoteImuController(
        transport: transport,
        profile: _profile(),
        screenOrientation: VrImuScreenOrientation.portraitUp,
        minimumSendInterval: Duration.zero,
        gyroscopeStreamOverride: gyroscope.stream,
        accelerometerStreamOverride: accelerometer.stream,
      );
    });

    tearDown(() async {
      await controller.stop();
      await gyroscope.close();
      await accelerometer.close();
    });

    test('sends profile and integrates gyroscope orientation', () async {
      await controller.start();
      expect(transport.sentProfiles, <VrControllerProfile>[_profile()]);

      final start = DateTime(2026, 1, 1);
      accelerometer.add(AccelerometerEvent(1, 2, 3, start));
      gyroscope.add(GyroscopeEvent(0, math.pi / 2, 0, start));
      gyroscope.add(
        GyroscopeEvent(
          0,
          math.pi / 2,
          0,
          start.add(const Duration(milliseconds: 100)),
        ),
      );
      await controller.flush();

      final frame = transport.sentFrames.last;
      const expectedAngle = math.pi / 20;
      expect(frame.qy, closeTo(math.sin(expectedAngle / 2), 1e-6));
      expect(frame.qw, closeTo(math.cos(expectedAngle / 2), 1e-6));
      expect(frame.accelerometer.x, 1);
      expect(frame.accelerometer.y, 2);
      expect(frame.accelerometer.z, 3);
    });

    test(
      'sends button/touch state and recenters without position drift',
      () async {
        await controller.start();
        controller.setButtonsBitset(5, sendImmediately: false);
        controller.setTouch(0.2, 0.8, sendImmediately: false);
        controller.sendCurrentState();
        await controller.flush();

        final frame = transport.sentFrames.last;
        expect(frame.buttonsBitset, 5);
        expect(frame.touchX, 0.2);
        expect(frame.touchY, 0.8);

        controller.recenter(sendImmediately: false);
        expect(controller.orientation.x, 0);
        expect(controller.orientation.y, 0);
        expect(controller.orientation.z, 0);
        expect(controller.orientation.w, 1);
      },
    );

    test('normalizes landscape sensor axes', () async {
      await controller.stop();
      controller = VrRemoteImuController(
        transport: transport,
        profile: _profile(),
        screenOrientation: VrImuScreenOrientation.landscapeLeft,
        minimumSendInterval: Duration.zero,
        gyroscopeStreamOverride: gyroscope.stream,
        accelerometerStreamOverride: accelerometer.stream,
      );
      await controller.start();
      final now = DateTime(2026, 1, 1);
      accelerometer.add(AccelerometerEvent(1, 2, 3, now));
      gyroscope.add(GyroscopeEvent(0, 0, 0, now));
      await controller.flush();

      expect(transport.sentFrames.last.accelerometer.x, 2);
      expect(transport.sentFrames.last.accelerometer.y, -1);
      expect(transport.sentFrames.last.accelerometer.z, 3);
    });

    test('requires a connected transport', () async {
      transport.state = VrTransportConnectionState.disconnected;
      await expectLater(controller.start(), throwsStateError);
      expect(controller.isRunning, isFalse);
    });
  });
}

VrControllerProfile _profile() => VrControllerProfile(
  deviceId: 'imu-phone',
  deviceName: 'IMU phone',
  widthMeters: 0.07,
  heightMeters: 0.15,
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
