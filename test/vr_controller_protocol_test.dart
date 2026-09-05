import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('VR controller protocol', () {
    test('round-trips a complete controller profile', () {
      final profile = _profile();

      final decoded = VrControllerProfile.fromJson(profile.toJson());

      expect(decoded, profile);
      expect(decoded.controls, hasLength(3));
      expect(decoded.controls.first.label, 'A');
      expect(
        () => decoded.controls.add(decoded.controls.first),
        throwsUnsupportedError,
      );
    });

    test('round-trips pose, optional touch, range, and orientation', () {
      final frame = VrRemotePoseFrame(
        sequence: 42,
        senderTimestampMicroseconds: 123456789,
        orientation: Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2),
        angularVelocity: Vector3(0.1, 0.2, 0.3),
        buttonsBitset: 5,
        touchX: 0.25,
        touchY: 0.75,
        rangeMeters: 0.62,
        rangeSource: VrRangeSource.bluetoothRssi,
        rangeConfidence: 0.35,
      );

      final decoded = VrRemotePoseFrame.fromJson(frame.toJson());

      expect(decoded, frame);
      expect(decoded.orientation.length, closeTo(1, 1e-7));
      expect(decoded.angularVelocity, Vector3(0.1, 0.2, 0.3));
    });

    test('codec round-trips every message kind', () {
      const codec = VrControllerMessageCodec();
      final event = VrInputEvent(
        type: VrInputType.pointerMove,
        source: VrInputSource.remotePhone,
        data: <String, dynamic>{
          'orientation': Quaternion.identity(),
          'forward': Vector3(0, 0, -1),
        },
      );
      final messages = <VrControllerMessage>[
        VrHelloMessage(sessionToken: 'secret', role: VrDeviceRole.child),
        const VrReadyMessage(),
        VrProfileMessage(_profile()),
        VrPoseMessage(
          VrRemotePoseFrame(
            sequence: 1,
            senderTimestampMicroseconds: 10,
            orientation: Quaternion.identity(),
          ),
        ),
        VrInputMessage(VrInputEventSnapshot.fromEvent(event)),
        const VrPingMessage(id: 7, sentTimestampMicroseconds: 11),
        const VrPongMessage(
          id: 7,
          sentTimestampMicroseconds: 11,
          responseTimestampMicroseconds: 12,
        ),
        const VrDisconnectMessage(reason: 'done'),
        VrErrorMessage(code: 'test', message: 'failure'),
      ];

      for (final message in messages) {
        final decoded = codec.decode(codec.encode(message));
        expect(decoded.runtimeType, message.runtimeType);
        expect(decoded.toJson(), message.toJson());
      }

      final input = codec.decode(codec.encode(messages[4])) as VrInputMessage;
      expect(input.event.data!['orientation'], isA<Quaternion>());
      expect(input.event.data!['forward'], Vector3(0, 0, -1));
    });

    test('snapshot owns copies of pooled mutable payload values', () {
      final orientation = Quaternion.identity();
      final forward = Vector3(0, 0, -1);
      final event = VrInputEvent(
        type: VrInputType.pointerMove,
        source: VrInputSource.remotePhone,
        data: <String, dynamic>{'orientation': orientation, 'forward': forward},
      );

      final snapshot = VrInputEventSnapshot.fromEvent(event);
      orientation.setValues(1, 0, 0, 0);
      forward.setValues(9, 9, 9);

      expect(snapshot.data!['orientation'], Quaternion.identity());
      expect(snapshot.data!['forward'], Vector3(0, 0, -1));
    });

    test('rejects invalid profiles, poses, and unknown messages', () {
      expect(
        () => VrControllerProfile(
          deviceId: 'phone',
          deviceName: 'Phone',
          widthMeters: 0.07,
          heightMeters: 0.15,
          controls: <VrControlDescriptor>[
            _control('same', 'A'),
            _control('same', 'B'),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => VrRemotePoseFrame(
          sequence: 0,
          senderTimestampMicroseconds: 0,
          orientation: Quaternion(0, 0, 0, 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => const VrControllerMessageCodec().decode('{"kind":"future"}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

VrControllerProfile _profile() => VrControllerProfile(
  deviceId: 'moto-g-controller',
  deviceName: 'Moto G',
  handedness: VrControllerHandedness.right,
  widthMeters: 0.074,
  heightMeters: 0.161,
  controls: <VrControlDescriptor>[
    _control('select', 'A'),
    VrControlDescriptor(
      id: 'back',
      label: 'B',
      kind: VrControlKind.button,
      x: 0.25,
      y: 0.75,
    ),
    VrControlDescriptor(
      id: 'touchpad',
      label: 'MOVE',
      kind: VrControlKind.touchpad,
      x: 0.5,
      y: 0.3,
      width: 0.7,
      height: 0.35,
    ),
  ],
);

VrControlDescriptor _control(String id, String label) => VrControlDescriptor(
  id: id,
  label: label,
  kind: VrControlKind.button,
  x: 0.75,
  y: 0.75,
);
