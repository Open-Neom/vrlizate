import 'dart:math';
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
      final originalRot = Quaternion.axisAngle(Vector3(0.577, 0.577, 0.577).normalized(), 1.25);
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
      expect(decoded.senderTimestampMicroseconds, equals(12345678 & 0xFFFFFFFF));
      expect(decoded.buttonsBitset, equals(0x00A3));

      // Orientation quaternion accuracy: dot product with original should be very close to 1.0
      final dot = (originalRot.x * decoded.qx +
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
    });

    test('detects binary packet headers correctly', () {
      final valid = codec.encodeHeartbeat(id: 1, timestampUs: 100);
      expect(VrRemoteBinaryCodec.isBinaryPacket(valid), isTrue);
      expect(VrRemoteBinaryCodec.inspectPacketType(valid), equals(VrRemoteBinaryCodec.packetTypeHeartbeat));

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
    });

    test('encodes heartbeat packets (12 bytes)', () {
      final ping = codec.encodeHeartbeat(id: 42, timestampUs: 1024, isPong: false);
      expect(ping.length, equals(VrRemoteBinaryCodec.heartbeatPacketLength));
      expect(ping[0], equals(VrRemoteBinaryCodec.magicByte));
      expect(ping[1], equals(VrRemoteBinaryCodec.packetTypeHeartbeat));
      expect(ping[2], equals(0)); // isPong = false

      final pong = codec.encodeHeartbeat(id: 42, timestampUs: 1024, isPong: true);
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
}
