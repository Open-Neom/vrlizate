import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('VrRemoteBinaryCodec', () {
    const codec = VrRemoteBinaryCodec();

    test('encodes pose frame to exactly 28 bytes', () {
      final frame = VrRemotePoseFrame(
        sequence: 1042,
        senderTimestampMicroseconds: 5000000,
        orientation: Quaternion.axisAngle(Vector3(0, 1, 0), pi / 4),
        angularVelocity: Vector3(0.5, -1.2, 0.0),
        buttonsBitset: 0x0005,
        touchX: 0.75,
        touchY: 0.25,
      );

      final bytes = codec.encodePose(frame);
      expect(bytes.length, equals(VrRemoteBinaryCodec.posePacketLength));
      expect(bytes[0], equals(VrRemoteBinaryCodec.magicByte));
      expect(bytes[1], equals(VrRemoteBinaryCodec.packetTypePose));
    });

    test('round-trips pose frame with high fidelity', () {
      final originalRot = Quaternion.axisAngle(
        Vector3(0.577, 0.577, 0.577).normalized(),
        1.25,
      );
      final frame = VrRemotePoseFrame(
        sequence: 32000,
        senderTimestampMicroseconds: 12345678,
        orientation: originalRot,
        angularVelocity: Vector3(12.5, -5.25, 0.1),
        buttonsBitset: 0x00A3,
        touchX: 0.88,
        touchY: 0.44,
      );

      final bytes = codec.encodePose(frame);
      final decoded = codec.decodePose(bytes);

      expect(decoded.sequence, equals(32000));
      // Timestamp lower 32 bits preserved
      expect(
        decoded.senderTimestampMicroseconds,
        equals(12345678 & 0xFFFFFFFF),
      );
      expect(decoded.buttonsBitset, equals(0x00A3));

      // Orientation quaternion accuracy: dot product with original should be very close to 1.0
      final dot =
          (originalRot.x * decoded.qx +
                  originalRot.y * decoded.qy +
                  originalRot.z * decoded.qz +
                  originalRot.w * decoded.qw)
              .abs();
      expect(dot, greaterThan(0.9999));

      // Angular velocity precision (scaled by 100.0)
      expect(decoded.angularVelocityX, closeTo(12.5, 0.02));
      expect(decoded.angularVelocityY, closeTo(-5.25, 0.02));
      expect(decoded.angularVelocityZ, closeTo(0.1, 0.02));

      // Touchpad precision
      expect(decoded.touchX, isNotNull);
      expect(decoded.touchX!, closeTo(0.88, 0.01));
      expect(decoded.touchY, isNotNull);
      expect(decoded.touchY!, closeTo(0.44, 0.01));
    });

    test('handles null touch coordinates with sentinel value', () {
      final frame = VrRemotePoseFrame(
        sequence: 1,
        senderTimestampMicroseconds: 1000,
        orientation: Quaternion.identity(),
        touchX: null,
        touchY: null,
      );

      final bytes = codec.encodePose(frame);
      final decoded = codec.decodePose(bytes);

      expect(decoded.touchX, isNull);
      expect(decoded.touchY, isNull);
      expect(ByteData.sublistView(bytes).getInt16(24), -32768);
      expect(ByteData.sublistView(bytes).getInt16(26), -32768);
    });

    test('round-trips every combination of touch endpoints and center', () {
      for (final x in [0.0, 0.5, 1.0]) {
        for (final y in [0.0, 0.5, 1.0]) {
          final decoded = codec.decodePose(
            codec.encodePose(
              VrRemotePoseFrame(
                sequence: 0,
                senderTimestampMicroseconds: 0,
                orientation: Quaternion.identity(),
                touchX: x,
                touchY: y,
              ),
            ),
          );
          expect(decoded.touchX, closeTo(x, 1 / 32767));
          expect(decoded.touchY, closeTo(y, 1 / 32767));
        }
      }
    });

    test('rejects truncated, oversized, and invalid touch pose packets', () {
      final bytes = codec.encodePose(
        VrRemotePoseFrame(
          sequence: 0,
          senderTimestampMicroseconds: 0,
          orientation: Quaternion.identity(),
        ),
      );
      for (final length in [0, 27, 29, 8192]) {
        expect(
          () => codec.decodePose(Uint8List(length)),
          throwsFormatException,
        );
      }
      // Touch coordinates are both null or both in 0..32767.
      for (final raw in [-32767, -1, 0, 32767]) {
        final malformed = Uint8List.fromList(bytes);
        ByteData.sublistView(malformed).setInt16(24, raw);
        expect(() => codec.decodePose(malformed), throwsFormatException);
      }
    });

    test('wire sequence wraps at 16 bits', () {
      for (final sequence in [65535, 65536, 65537]) {
        final decoded = codec.decodePose(
          codec.encodePose(
            VrRemotePoseFrame(
              sequence: sequence,
              senderTimestampMicroseconds: 0,
              orientation: Quaternion.identity(),
            ),
          ),
        );
        expect(decoded.sequence, sequence & 0xFFFF);
      }
    });

    test('detects binary packet headers correctly', () {
      final valid = codec.encodeHeartbeat(id: 1, timestampUs: 100);
      expect(VrRemoteBinaryCodec.isBinaryPacket(valid), isTrue);
      expect(
        VrRemoteBinaryCodec.inspectPacketType(valid),
        equals(VrRemoteBinaryCodec.packetTypeHeartbeat),
      );

      final invalid = [0x7B, 0x22]; // '{"' (JSON start)
      expect(VrRemoteBinaryCodec.isBinaryPacket(invalid), isFalse);
      expect(VrRemoteBinaryCodec.inspectPacketType(invalid), isNull);
    });

    test('encodes and decodes discrete input events (16 bytes)', () {
      final snapshot = VrInputEventSnapshot.fromEvent(
        VrInputEvent(
          type: VrInputType.trigger,
          source: VrInputSource.remotePhone,
          active: true,
          timestamp: DateTime.fromMicrosecondsSinceEpoch(999999),
        ),
      );

      final bytes = codec.encodeInputEvent(snapshot);
      expect(bytes.length, equals(VrRemoteBinaryCodec.inputPacketLength));

      final decoded = codec.decodeInputEvent(bytes);
      expect(decoded.type, equals(VrInputType.trigger));
      expect(decoded.source, equals(VrInputSource.remotePhone));
      expect(decoded.active, isTrue);
      for (final length in [15, 17]) {
        expect(
          () => codec.decodeInputEvent(Uint8List(length)),
          throwsFormatException,
        );
      }
    });

    test('encodes heartbeat packets (12 bytes)', () {
      final ping = codec.encodeHeartbeat(
        id: 42,
        timestampUs: 1024,
        isPong: false,
      );
      expect(ping.length, equals(VrRemoteBinaryCodec.heartbeatPacketLength));
      expect(ping[0], equals(VrRemoteBinaryCodec.magicByte));
      expect(ping[1], equals(VrRemoteBinaryCodec.packetTypeHeartbeat));
      expect(ping[2], equals(0)); // isPong = false

      final pong = codec.encodeHeartbeat(
        id: 42,
        timestampUs: 1024,
        isPong: true,
      );
      expect(pong[2], equals(1)); // isPong = true
    });
  });

  group('VrExternalRenderTargetDescriptor', () {
    test('constructs valid descriptor and calculates aspect ratio', () {
      const desc = VrExternalRenderTargetDescriptor(
        backend: VrGpuBackend.openGlEs,
        format: VrGpuTextureFormat.rgba8,
        width: 1920,
        height: 1080,
        sampleCount: 1,
      );

      expect(desc.backend, equals(VrGpuBackend.openGlEs));
      expect(desc.format, equals(VrGpuTextureFormat.rgba8));
      expect(desc.width, equals(1920));
      expect(desc.height, equals(1080));
      expect(desc.aspectRatio, closeTo(1920 / 1080, 0.001));
      expect(desc.isArrayTexture, isFalse);

      final json = desc.toJson();
      expect(json['backend'], equals('openGlEs'));
      expect(json['format'], equals('rgba8'));
      expect(json['width'], equals(1920));
    });

    test('equality and hashCode work as expected', () {
      const desc1 = VrExternalRenderTargetDescriptor(
        backend: VrGpuBackend.vulkan,
        format: VrGpuTextureFormat.srgb8Alpha8,
        width: 2048,
        height: 2048,
      );
      const desc2 = VrExternalRenderTargetDescriptor(
        backend: VrGpuBackend.vulkan,
        format: VrGpuTextureFormat.srgb8Alpha8,
        width: 2048,
        height: 2048,
      );
      const desc3 = VrExternalRenderTargetDescriptor(
        backend: VrGpuBackend.vulkan,
        format: VrGpuTextureFormat.rgba16f,
        width: 2048,
        height: 2048,
      );

      expect(desc1, equals(desc2));
      expect(desc1.hashCode, equals(desc2.hashCode));
      expect(desc1, isNot(equals(desc3)));
    });
  });

  group('VrSmallestThreeQuaternion & VrCompactGamepadCodec', () {
    test('packs unit quaternions across all 4 dominant components within < 0.15 deg (exact 0 on identity)', () {
      final idUnpacked = VrSmallestThreeQuaternion.unpack(
        VrSmallestThreeQuaternion.pack(Quaternion.identity()),
      );
      expect(idUnpacked.x, 0.0);
      expect(idUnpacked.y, 0.0);
      expect(idUnpacked.z, 0.0);
      expect(idUnpacked.w, 1.0);

      final samples = <Quaternion>[
        Quaternion.identity(),
        Quaternion.axisAngle(Vector3(1, 0, 0), pi * 0.85),
        Quaternion.axisAngle(Vector3(0, 1, 0), pi * 0.88),
        Quaternion.axisAngle(Vector3(0, 0, 1), pi * 0.90),
        Quaternion.axisAngle(Vector3(0.4, -0.7, 0.58).normalized(), 1.35),
        Quaternion.axisAngle(Vector3(-0.8, 0.2, -0.55).normalized(), 2.40),
      ];

      for (final q in samples) {
        final packed = VrSmallestThreeQuaternion.pack(q);
        expect(packed, inInclusiveRange(0, 0xFFFFFFFF));
        final unpacked = VrSmallestThreeQuaternion.unpack(packed);
        final dot = (q.x * unpacked.x +
                q.y * unpacked.y +
                q.z * unpacked.z +
                q.w * unpacked.w)
            .abs()
            .clamp(0.0, 1.0);
        final angleDeg = 2.0 * acos(dot) * 180.0 / pi;
        expect(angleDeg, lessThan(0.15));
      }
    });

    test('encodes full gamepad state into 46 bytes (-94% vs JSON) and round-trips', () {
      const codec = VrCompactGamepadCodec();
      final rot = Quaternion.axisAngle(
        Vector3(0.3, 0.8, -0.5).normalized(),
        1.1,
      );
      final frame = VrCompactGamepadFrame(
        sequence: 54321,
        senderTimestampMicroseconds: 98765432,
        orientation: rot,
        angularVelocity: Vector3(2.4, -1.8, 0.6),
        stickX: -0.72,
        stickY: 0.48,
        lookX: 0.35,
        lookY: -0.90,
        laserX: 0.22,
        laserY: -0.15,
        steering: -0.64,
        drivingTilt: 0.28,
        throttle: 0.82,
        brake: 0.12,
        passthroughMix: 0.60,
        passthroughActive: true,
        spatialHudVisible: true,
        modeIndex: 2,
        hostModeRevision: 12,
        trigger: true,
        btnA: true,
        btnB: false,
        btnX: true,
        btnY: false,
        btnGrip: true,
        laserSlideActive: true,
        motionAvailable: true,
        rangeMeters: 0.48,
      );

      final encoded = codec.encode(frame);
      expect(encoded.length, VrCompactGamepadCodec.packetLength);
      expect(encoded.length, 46);
      expect(
        VrRemoteBinaryCodec.inspectPacketType(encoded),
        VrRemoteBinaryCodec.packetTypeFullGamepad,
      );

      final decoded = codec.tryDecode(encoded)!;
      expect(decoded.sequence, 54321);
      expect(decoded.stickX, closeTo(-0.72, 0.001));
      expect(decoded.stickY, closeTo(0.48, 0.001));
      expect(decoded.lookX, closeTo(0.35, 0.001));
      expect(decoded.lookY, closeTo(-0.90, 0.001));
      expect(decoded.laserX, closeTo(0.22, 0.001));
      expect(decoded.laserY, closeTo(-0.15, 0.001));
      expect(decoded.steering, closeTo(-0.64, 0.001));
      expect(decoded.drivingTilt, closeTo(0.28, 0.01));
      expect(decoded.throttle, closeTo(0.82, 0.005));
      expect(decoded.brake, closeTo(0.12, 0.005));
      expect(decoded.passthroughMix, closeTo(0.60, 0.005));
      expect(decoded.passthroughActive, isTrue);
      expect(decoded.spatialHudVisible, isTrue);
      expect(decoded.modeIndex, 2);
      expect(decoded.hostModeRevision, 12);
      expect(decoded.trigger, isTrue);
      expect(decoded.btnA, isTrue);
      expect(decoded.btnB, isFalse);
      expect(decoded.btnX, isTrue);
      expect(decoded.btnGrip, isTrue);
      expect(decoded.laserSlideActive, isTrue);
      expect(decoded.motionAvailable, isTrue);
      expect(decoded.rangeMeters, closeTo(0.48, 0.01));

      final dot = (rot.x * decoded.orientation.x +
              rot.y * decoded.orientation.y +
              rot.z * decoded.orientation.z +
              rot.w * decoded.orientation.w)
          .abs();
      expect(dot, greaterThan(0.9999));
    });
  });
}
