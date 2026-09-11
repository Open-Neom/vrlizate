import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../input/vr_input_event_bus.dart';
import 'vr_controller_protocol.dart';

/// Binary wire protocol for high-frequency VRlizate controller streaming.
///
/// Designed to eliminate JSON serialization overhead and GC pressure at 60-120 Hz.
/// Standard pose frame payload is exactly 28 bytes.
class VrRemoteBinaryCodec {
  static const int magicByte = 0x56; // ASCII 'V'
  static const int packetTypePose = 0x01;
  static const int packetTypeInput = 0x02;
  static const int packetTypeHeartbeat = 0x03;

  static const int posePacketLength = 28;
  static const int inputPacketLength = 16;
  static const int heartbeatPacketLength = 12;

  static const double _quatScale = 32767.0;
  static const double _angVelScale = 100.0;
  static const double _touchScale = 32767.0;

  const VrRemoteBinaryCodec();

  /// Checks whether [bytes] starts with the VRlizate binary protocol magic byte.
  static bool isBinaryPacket(List<int> bytes) {
    return bytes.length >= 2 && bytes[0] == magicByte;
  }

  /// Returns the packet type of a binary payload, or null if invalid.
  static int? inspectPacketType(List<int> bytes) {
    if (!isBinaryPacket(bytes)) return null;
    return bytes[1];
  }

  /// Encodes a [VrRemotePoseFrame] into a compact 28-byte [Uint8List].
  Uint8List encodePose(VrRemotePoseFrame frame) {
    final buffer = Uint8List(posePacketLength);
    final data = ByteData.sublistView(buffer);

    data.setUint8(0, magicByte);
    data.setUint8(1, packetTypePose);
    data.setUint16(2, frame.sequence & 0xFFFF, Endian.big);
    data.setUint32(4, frame.senderTimestampMicroseconds & 0xFFFFFFFF, Endian.big);

    // Orientation Quaternion: 4 x int16 (-1.0 .. 1.0 mapped to -32767 .. 32767)
    data.setInt16(8, (frame.qx.clamp(-1.0, 1.0) * _quatScale).round(), Endian.big);
    data.setInt16(10, (frame.qy.clamp(-1.0, 1.0) * _quatScale).round(), Endian.big);
    data.setInt16(12, (frame.qz.clamp(-1.0, 1.0) * _quatScale).round(), Endian.big);
    data.setInt16(14, (frame.qw.clamp(-1.0, 1.0) * _quatScale).round(), Endian.big);

    // Angular velocity: 3 x int16 (scaled by 100.0)
    data.setInt16(16, (frame.angularVelocityX * _angVelScale).clamp(-32768, 32767).round(), Endian.big);
    data.setInt16(18, (frame.angularVelocityY * _angVelScale).clamp(-32768, 32767).round(), Endian.big);
    data.setInt16(20, (frame.angularVelocityZ * _angVelScale).clamp(-32768, 32767).round(), Endian.big);

    // Buttons bitset: uint16
    data.setUint16(22, frame.buttonsBitset & 0xFFFF, Endian.big);

    // Touchpad / Stick: 2 x int16 (0.0 .. 1.0 mapped to 0 .. 32767)
    final tx = frame.touchX != null
        ? (frame.touchX!.clamp(0.0, 1.0) * _touchScale).round()
        : 0x7FFF; // 0x7FFF sentinel indicates null
    final ty = frame.touchY != null
        ? (frame.touchY!.clamp(0.0, 1.0) * _touchScale).round()
        : 0x7FFF;
    data.setInt16(24, tx, Endian.big);
    data.setInt16(26, ty, Endian.big);

    return buffer;
  }

  /// Decodes a 28-byte [Uint8List] into a [VrRemotePoseFrame].
  VrRemotePoseFrame decodePose(Uint8List bytes) {
    if (bytes.length < posePacketLength) {
      throw FormatException(
        'Binary pose packet too short: expected $posePacketLength bytes, got ${bytes.length}',
      );
    }
    final data = ByteData.sublistView(bytes);
    final magic = data.getUint8(0);
    final type = data.getUint8(1);
    if (magic != magicByte || type != packetTypePose) {
      throw FormatException('Invalid pose packet header: magic 0x${magic.toRadixString(16)}, type 0x${type.toRadixString(16)}');
    }

    final sequence = data.getUint16(2, Endian.big);
    final timestamp = data.getUint32(4, Endian.big);

    final qx = data.getInt16(8, Endian.big) / _quatScale;
    final qy = data.getInt16(10, Endian.big) / _quatScale;
    final qz = data.getInt16(12, Endian.big) / _quatScale;
    final qw = data.getInt16(14, Endian.big) / _quatScale;

    final avx = data.getInt16(16, Endian.big) / _angVelScale;
    final avy = data.getInt16(18, Endian.big) / _angVelScale;
    final avz = data.getInt16(20, Endian.big) / _angVelScale;

    final buttons = data.getUint16(22, Endian.big);

    final rawTx = data.getInt16(24, Endian.big);
    final rawTy = data.getInt16(26, Endian.big);
    final double? touchX = rawTx == 0x7FFF ? null : (rawTx / _touchScale).clamp(0.0, 1.0);
    final double? touchY = rawTy == 0x7FFF ? null : (rawTy / _touchScale).clamp(0.0, 1.0);

    return VrRemotePoseFrame(
      sequence: sequence,
      senderTimestampMicroseconds: timestamp,
      orientation: Quaternion(qx, qy, qz, qw),
      angularVelocity: Vector3(avx, avy, avz),
      buttonsBitset: buttons,
      touchX: touchX,
      touchY: touchY,
    );
  }

  /// Encodes a discrete input action event into a 16-byte [Uint8List].
  Uint8List encodeInputEvent(VrInputEventSnapshot snapshot) {
    final buffer = Uint8List(inputPacketLength);
    final data = ByteData.sublistView(buffer);

    data.setUint8(0, magicByte);
    data.setUint8(1, packetTypeInput);
    data.setUint8(2, snapshot.type.index & 0xFF);
    data.setUint8(3, snapshot.source.index & 0xFF);
    data.setUint8(4, snapshot.active ? 1 : 0);
    data.setUint8(5, 0); // reserved

    // Sequence / hash of targetId (first 2 bytes)
    final targetHash = snapshot.targetId != null ? snapshot.targetId.hashCode & 0xFFFF : 0;
    data.setUint16(6, targetHash, Endian.big);

    // Timestamp (lower 32 bits)
    data.setUint32(8, snapshot.timestampMicrosecondsSinceEpoch & 0xFFFFFFFF, Endian.big);

    // Reserved for value / analog float
    data.setFloat32(12, 0.0, Endian.big);

    return buffer;
  }

  /// Decodes a 16-byte [Uint8List] into a discrete input event.
  VrInputEventSnapshot decodeInputEvent(Uint8List bytes) {
    if (bytes.length < inputPacketLength) {
      throw FormatException(
        'Binary input packet too short: expected $inputPacketLength bytes, got ${bytes.length}',
      );
    }
    final data = ByteData.sublistView(bytes);
    final magic = data.getUint8(0);
    final type = data.getUint8(1);
    if (magic != magicByte || type != packetTypeInput) {
      throw FormatException('Invalid input packet header: magic 0x${magic.toRadixString(16)}, type 0x${type.toRadixString(16)}');
    }

    final typeIdx = data.getUint8(2);
    final sourceIdx = data.getUint8(3);
    final active = data.getUint8(4) != 0;
    final timestamp = data.getUint32(8, Endian.big);

    final inputType = typeIdx < VrInputType.values.length ? VrInputType.values[typeIdx] : VrInputType.select;
    final inputSource = sourceIdx < VrInputSource.values.length ? VrInputSource.values[sourceIdx] : VrInputSource.remotePhone;

    return VrInputEventSnapshot.fromEvent(
      VrInputEvent(
        type: inputType,
        source: inputSource,
        active: active,
        timestamp: DateTime.fromMicrosecondsSinceEpoch(timestamp),
      ),
    );
  }

  /// Encodes a 12-byte heartbeat (Ping/Pong) packet.
  Uint8List encodeHeartbeat({required int id, required int timestampUs, bool isPong = false}) {
    final buffer = Uint8List(heartbeatPacketLength);
    final data = ByteData.sublistView(buffer);

    data.setUint8(0, magicByte);
    data.setUint8(1, packetTypeHeartbeat);
    data.setUint8(2, isPong ? 1 : 0);
    data.setUint8(3, 0); // reserved
    data.setUint32(4, id & 0xFFFFFFFF, Endian.big);
    data.setUint32(8, timestampUs & 0xFFFFFFFF, Endian.big);

    return buffer;
  }
}
