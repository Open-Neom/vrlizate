import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../input/vr_input_event_bus.dart';
import 'vr_controller_protocol.dart';

/// Experimental binary wire codec for compact VRlizate pose streaming.
///
/// A pose is exactly 28 bytes, but is not a full gamepad state: it has no mode,
/// second stick, range, or recenter command. JSON remains the full-state route
/// in vrlizate_joystick. Encoding/decoding allocates; this is not a Zero-GC API.
/// Sequences and sender timestamps contain only their lower 16 and 32 bits.
/// Receivers must compare sequences modulo 65536 (a forward gap < 32768).
///
/// Null touch coordinates use signed -32768; 0..32767 encode the full 0..1
/// range. The previous experimental +32767 sentinel was ambiguous with 1.0
/// and is not supported: update experimental senders and receivers together.
class VrRemoteBinaryCodec {
  static const int magicByte = 0x56; // ASCII 'V'
  static const int packetTypePose = 0x01;
  static const int packetTypeInput = 0x02;
  static const int packetTypeHeartbeat = 0x03;
  static const int packetTypeFullGamepad = 0x04;

  static const int posePacketLength = 28;
  static const int inputPacketLength = 16;
  static const int heartbeatPacketLength = 12;
  static const int fullGamepadPacketLength = 46;

  static const double _quatScale = 32767.0;
  static const double _angVelScale = 100.0;
  static const double _touchScale = 32767.0;
  static const int _nullTouch = -32768;

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
    data.setUint32(
      4,
      frame.senderTimestampMicroseconds & 0xFFFFFFFF,
      Endian.big,
    );

    // Orientation Quaternion: 4 x int16 (-1.0 .. 1.0 mapped to -32767 .. 32767)
    data.setInt16(
      8,
      (frame.qx.clamp(-1.0, 1.0) * _quatScale).round(),
      Endian.big,
    );
    data.setInt16(
      10,
      (frame.qy.clamp(-1.0, 1.0) * _quatScale).round(),
      Endian.big,
    );
    data.setInt16(
      12,
      (frame.qz.clamp(-1.0, 1.0) * _quatScale).round(),
      Endian.big,
    );
    data.setInt16(
      14,
      (frame.qw.clamp(-1.0, 1.0) * _quatScale).round(),
      Endian.big,
    );

    // Angular velocity: 3 x int16 (scaled by 100.0)
    data.setInt16(
      16,
      (frame.angularVelocityX * _angVelScale).clamp(-32768, 32767).round(),
      Endian.big,
    );
    data.setInt16(
      18,
      (frame.angularVelocityY * _angVelScale).clamp(-32768, 32767).round(),
      Endian.big,
    );
    data.setInt16(
      20,
      (frame.angularVelocityZ * _angVelScale).clamp(-32768, 32767).round(),
      Endian.big,
    );

    // Buttons bitset: uint16
    data.setUint16(22, frame.buttonsBitset & 0xFFFF, Endian.big);

    // Touchpad / Stick: 2 x int16 (0.0 .. 1.0 mapped to 0 .. 32767)
    final tx = frame.touchX != null
        ? (frame.touchX!.clamp(0.0, 1.0) * _touchScale).round()
        : _nullTouch;
    final ty = frame.touchY != null
        ? (frame.touchY!.clamp(0.0, 1.0) * _touchScale).round()
        : _nullTouch;
    data.setInt16(24, tx, Endian.big);
    data.setInt16(26, ty, Endian.big);

    return buffer;
  }

  /// Decodes a 28-byte [Uint8List] into a [VrRemotePoseFrame].
  VrRemotePoseFrame decodePose(Uint8List bytes) {
    if (bytes.length != posePacketLength) {
      throw FormatException(
        'Invalid binary pose length: expected exactly $posePacketLength bytes, got ${bytes.length}',
      );
    }
    final data = ByteData.sublistView(bytes);
    final magic = data.getUint8(0);
    final type = data.getUint8(1);
    if (magic != magicByte || type != packetTypePose) {
      throw FormatException(
        'Invalid pose packet header: magic 0x${magic.toRadixString(16)}, type 0x${type.toRadixString(16)}',
      );
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
    if ((rawTx < 0 && rawTx != _nullTouch) ||
        (rawTy < 0 && rawTy != _nullTouch) ||
        ((rawTx == _nullTouch) != (rawTy == _nullTouch))) {
      throw const FormatException('Invalid binary touch coordinate pair.');
    }
    final double? touchX = rawTx == _nullTouch ? null : rawTx / _touchScale;
    final double? touchY = rawTy == _nullTouch ? null : rawTy / _touchScale;

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
    final targetHash = snapshot.targetId != null
        ? snapshot.targetId.hashCode & 0xFFFF
        : 0;
    data.setUint16(6, targetHash, Endian.big);

    // Timestamp (lower 32 bits)
    data.setUint32(
      8,
      snapshot.timestampMicrosecondsSinceEpoch & 0xFFFFFFFF,
      Endian.big,
    );

    // Reserved for value / analog float
    data.setFloat32(12, 0.0, Endian.big);

    return buffer;
  }

  /// Decodes a 16-byte [Uint8List] into a discrete input event.
  VrInputEventSnapshot decodeInputEvent(Uint8List bytes) {
    if (bytes.length != inputPacketLength) {
      throw FormatException(
        'Invalid binary input length: expected exactly $inputPacketLength bytes, got ${bytes.length}',
      );
    }
    final data = ByteData.sublistView(bytes);
    final magic = data.getUint8(0);
    final type = data.getUint8(1);
    if (magic != magicByte || type != packetTypeInput) {
      throw FormatException(
        'Invalid input packet header: magic 0x${magic.toRadixString(16)}, type 0x${type.toRadixString(16)}',
      );
    }

    final typeIdx = data.getUint8(2);
    final sourceIdx = data.getUint8(3);
    final active = data.getUint8(4) != 0;
    final timestamp = data.getUint32(8, Endian.big);

    final inputType = typeIdx < VrInputType.values.length
        ? VrInputType.values[typeIdx]
        : VrInputType.select;
    final inputSource = sourceIdx < VrInputSource.values.length
        ? VrInputSource.values[sourceIdx]
        : VrInputSource.remotePhone;

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
  Uint8List encodeHeartbeat({
    required int id,
    required int timestampUs,
    bool isPong = false,
  }) {
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

/// Lossless-grade 32-bit (`4-byte`) "Smallest-Three" unit quaternion codec.
///
/// Exploits $q_x^2 + q_y^2 + q_z^2 + q_w^2 = 1$: omits the largest-magnitude
/// component (`2 bits` index) with sign normalization ($q_{\max} \ge 0$), and
/// quantizes the remaining three components in $[-1/\sqrt{2}, +1/\sqrt{2}]$ to
/// `10 bits` each (`2 + 3 × 10 = 32 bits`, max angular error `< 0.06°`).
abstract final class VrSmallestThreeQuaternion {
  static const double _invSqrt2 = 0.7071067811865475;
  static const int _mask10 = 0x3FF;
  static const int _halfRange = 511;

  static int pack(Quaternion q) {
    var x = q.x;
    var y = q.y;
    var z = q.z;
    var w = q.w;
    final len2 = x * x + y * y + z * z + w * w;
    if (!len2.isFinite || len2 < 1e-12) {
      return (3 << 30) | (_halfRange << 20) | (_halfRange << 10) | _halfRange;
    }
    final invLen = 1.0 / math.sqrt(len2);
    x *= invLen;
    y *= invLen;
    z *= invLen;
    w *= invLen;

    final c = <double>[x, y, z, w];
    var maxIdx = 0;
    var maxAbs = x.abs();
    for (var i = 1; i < 4; i++) {
      final a = c[i].abs();
      if (a > maxAbs) {
        maxAbs = a;
        maxIdx = i;
      }
    }
    final sign = c[maxIdx] < 0.0 ? -1.0 : 1.0;
    var out = maxIdx << 30;
    var shift = 20;
    for (var i = 0; i < 4; i++) {
      if (i == maxIdx) continue;
      final v = (c[i] * sign).clamp(-_invSqrt2, _invSqrt2);
      final signedInt = ((v / _invSqrt2) * _halfRange).round().clamp(
        -_halfRange,
        _halfRange,
      );
      final q10 = signedInt + _halfRange;
      out |= (q10 << shift);
      shift -= 10;
    }
    return out >>> 0;
  }

  static Quaternion unpack(int packed32) {
    final maxIdx = (packed32 >>> 30) & 0x3;
    final q0 = (packed32 >>> 20) & _mask10;
    final q1 = (packed32 >>> 10) & _mask10;
    final q2 = packed32 & _mask10;

    double dequant(int q) =>
        (((q - _halfRange) / _halfRange).clamp(-1.0, 1.0)) * _invSqrt2;

    final a = dequant(q0);
    final b = dequant(q1);
    final d = dequant(q2);
    final rem = 1.0 - (a * a + b * b + d * d);
    final largest = rem > 0.0 ? math.sqrt(rem) : 0.0;

    return switch (maxIdx) {
      0 => Quaternion(largest, a, b, d),
      1 => Quaternion(a, largest, b, d),
      2 => Quaternion(a, b, largest, d),
      _ => Quaternion(a, b, d, largest),
    };
  }
}

/// Complete 120 Hz dual-stick + IMU + driving + passthrough controller snapshot
/// packed into `46 bytes` (`-94%` vs `~780-byte` JSON UTF-8).
class VrCompactGamepadFrame {
  const VrCompactGamepadFrame({
    required this.sequence,
    required this.senderTimestampMicroseconds,
    required this.orientation,
    required this.angularVelocity,
    this.stickX = 0.0,
    this.stickY = 0.0,
    this.lookX = 0.0,
    this.lookY = 0.0,
    this.laserX = 0.0,
    this.laserY = 0.0,
    this.steering = 0.0,
    this.drivingTilt = 0.0,
    this.throttle = 0.0,
    this.brake = 0.0,
    this.modeIndex = 0,
    this.hostModeRevision,
    this.trigger = false,
    this.action = false,
    this.btnA = false,
    this.btnB = false,
    this.btnX = false,
    this.btnY = false,
    this.btnL = false,
    this.btnR = false,
    this.btnZL = false,
    this.btnZR = false,
    this.btnGrip = false,
    this.stickClick = false,
    this.recenter = false,
    this.moveAtEdge = false,
    this.dpadUp = false,
    this.dpadDown = false,
    this.dpadLeft = false,
    this.dpadRight = false,
    this.laserSlideActive = false,
    this.pointerPoseReady = false,
    this.controllerVisible = true,
    this.drivingPaused = false,
    this.motionAvailable = false,
    this.passthroughActive = false,
    this.spatialHudVisible = false,
    this.passthroughMix = 0.0,
    this.rangeMeters,
  });

  final int sequence;
  final int senderTimestampMicroseconds;
  final Quaternion orientation;
  final Vector3 angularVelocity;
  final double stickX;
  final double stickY;
  final double lookX;
  final double lookY;
  final double laserX;
  final double laserY;
  final double steering;
  final double drivingTilt;
  final double throttle;
  final double brake;

  /// `0 = joystick`, `1 = laser`, `2 = driving`, `3 = nes`.
  final int modeIndex;
  final int? hostModeRevision;

  final bool trigger;
  final bool action;
  final bool btnA;
  final bool btnB;
  final bool btnX;
  final bool btnY;
  final bool btnL;
  final bool btnR;
  final bool btnZL;
  final bool btnZR;
  final bool btnGrip;
  final bool stickClick;
  final bool recenter;
  final bool moveAtEdge;
  final bool dpadUp;
  final bool dpadDown;
  final bool dpadLeft;
  final bool dpadRight;
  final bool laserSlideActive;

  double get dpadX => (dpadRight ? 1.0 : 0.0) - (dpadLeft ? 1.0 : 0.0);
  double get dpadY => (dpadUp ? 1.0 : 0.0) - (dpadDown ? 1.0 : 0.0);

  /// Sender-observed upright landscape posture at snapshot creation.
  /// Legacy senders default false; this is not heading or positional tracking.
  final bool pointerPoseReady;
  final bool controllerVisible;
  final bool drivingPaused;
  final bool motionAvailable;
  final bool passthroughActive;
  final bool spatialHudVisible;
  final double passthroughMix;
  final double? rangeMeters;
}

/// Zero-JSON `46-byte` binary codec for [VrCompactGamepadFrame].
class VrCompactGamepadCodec {
  const VrCompactGamepadCodec();

  static const int packetLength = VrRemoteBinaryCodec.fullGamepadPacketLength;
  static const double _axisScale = 32767.0;
  static const double _angVelScale = 300.0;

  static bool isCompactGamepadPacket(List<int> bytes) =>
      bytes.length == packetLength &&
      bytes[0] == VrRemoteBinaryCodec.magicByte &&
      bytes[1] == VrRemoteBinaryCodec.packetTypeFullGamepad;

  static int _qAxis(double v) =>
      (v.clamp(-1.0, 1.0) * _axisScale).round().clamp(-32767, 32767);

  static double _dqAxis(int v) {
    final d = (v / _axisScale).clamp(-1.0, 1.0);
    return d.abs() < 0.0005 ? 0.0 : d;
  }

  Uint8List encode(VrCompactGamepadFrame f) {
    final buf = Uint8List(packetLength);
    final bd = ByteData.sublistView(buf);
    buf[0] = VrRemoteBinaryCodec.magicByte;
    buf[1] = VrRemoteBinaryCodec.packetTypeFullGamepad;
    bd.setUint32(2, f.sequence & 0xFFFFFFFF, Endian.little);
    bd.setUint32(6, f.senderTimestampMicroseconds & 0xFFFFFFFF, Endian.little);
    bd.setUint32(
      10,
      VrSmallestThreeQuaternion.pack(f.orientation),
      Endian.little,
    );

    bd.setInt16(
      14,
      (f.angularVelocity.x * _angVelScale).round().clamp(-32767, 32767),
      Endian.little,
    );
    bd.setInt16(
      16,
      (f.angularVelocity.y * _angVelScale).round().clamp(-32767, 32767),
      Endian.little,
    );
    bd.setInt16(
      18,
      (f.angularVelocity.z * _angVelScale).round().clamp(-32767, 32767),
      Endian.little,
    );

    bd.setInt16(20, _qAxis(f.stickX), Endian.little);
    bd.setInt16(22, _qAxis(f.stickY), Endian.little);
    bd.setInt16(24, _qAxis(f.lookX), Endian.little);
    bd.setInt16(26, _qAxis(f.lookY), Endian.little);
    bd.setInt16(28, _qAxis(f.laserX), Endian.little);
    bd.setInt16(30, _qAxis(f.laserY), Endian.little);
    bd.setInt16(32, _qAxis(f.steering), Endian.little);

    bd.setInt8(34, (f.drivingTilt.clamp(-1.0, 1.0) * 127.0).round());
    buf[35] = (f.throttle.clamp(0.0, 1.0) * 255.0).round();
    buf[36] = (f.brake.clamp(0.0, 1.0) * 255.0).round();

    final hasRev = f.hostModeRevision != null && f.hostModeRevision! >= 0;
    var modeFlags = (f.modeIndex.clamp(0, 7)) | (hasRev ? 0x80 : 0);
    if (f.dpadUp) modeFlags |= 1 << 3;
    if (f.dpadDown) modeFlags |= 1 << 4;
    if (f.dpadLeft) modeFlags |= 1 << 5;
    if (f.dpadRight) modeFlags |= 1 << 6;
    buf[37] = modeFlags;
    bd.setUint16(
      38,
      hasRev ? (f.hostModeRevision! & 0xFFFF) : 0,
      Endian.little,
    );

    var flags16 = 0;
    if (f.trigger) flags16 |= 1 << 0;
    if (f.action) flags16 |= 1 << 1;
    if (f.btnA) flags16 |= 1 << 2;
    if (f.btnB) flags16 |= 1 << 3;
    if (f.btnX) flags16 |= 1 << 4;
    if (f.btnY) flags16 |= 1 << 5;
    if (f.btnL) flags16 |= 1 << 6;
    if (f.btnR) flags16 |= 1 << 7;
    if (f.btnGrip) flags16 |= 1 << 8;
    if (f.stickClick) flags16 |= 1 << 9;
    if (f.recenter) flags16 |= 1 << 10;
    if (f.moveAtEdge) flags16 |= 1 << 11;
    if (f.laserSlideActive) flags16 |= 1 << 12;
    if (f.controllerVisible) flags16 |= 1 << 13;
    if (f.drivingPaused) flags16 |= 1 << 14;
    if (f.motionAvailable) flags16 |= 1 << 15;
    bd.setUint16(40, flags16, Endian.little);

    final validRange =
        f.rangeMeters != null && f.rangeMeters!.isFinite && f.rangeMeters! > 0;
    var flags8 = 0;
    if (f.passthroughActive) flags8 |= 1 << 0;
    if (f.spatialHudVisible) flags8 |= 1 << 1;
    if (validRange) flags8 |= 1 << 2;
    if (f.pointerPoseReady) flags8 |= 1 << 3;
    if (f.btnZL) flags8 |= 1 << 4;
    if (f.btnZR) flags8 |= 1 << 5;
    buf[42] = flags8;
    buf[43] = (f.passthroughMix.clamp(0.0, 1.0) * 255.0).round();
    bd.setUint16(
      44,
      validRange ? (f.rangeMeters! * 1000.0).round().clamp(1, 65535) : 0,
      Endian.little,
    );
    return buf;
  }

  VrCompactGamepadFrame? tryDecode(Uint8List bytes) {
    if (!isCompactGamepadPacket(bytes)) return null;
    final bd = ByteData.sublistView(bytes);
    final seq = bd.getUint32(2, Endian.little);
    final ts = bd.getUint32(6, Endian.little);
    final q = VrSmallestThreeQuaternion.unpack(bd.getUint32(10, Endian.little));
    final wx = bd.getInt16(14, Endian.little) / _angVelScale;
    final wy = bd.getInt16(16, Endian.little) / _angVelScale;
    final wz = bd.getInt16(18, Endian.little) / _angVelScale;
    if (wx.abs() > 100.0 || wy.abs() > 100.0 || wz.abs() > 100.0) {
      return null;
    }

    final modeByte = bytes[37];
    final hasRev = (modeByte & 0x80) != 0;
    final modeIdx = modeByte & 0x07;
    final rev = hasRev ? bd.getUint16(38, Endian.little) : null;

    final f16 = bd.getUint16(40, Endian.little);
    final f8 = bytes[42];
    final hasRange = (f8 & (1 << 2)) != 0;
    final rangeMm = bd.getUint16(44, Endian.little);

    return VrCompactGamepadFrame(
      sequence: seq,
      senderTimestampMicroseconds: ts,
      orientation: q,
      angularVelocity: Vector3(wx, wy, wz),
      stickX: _dqAxis(bd.getInt16(20, Endian.little)),
      stickY: _dqAxis(bd.getInt16(22, Endian.little)),
      lookX: _dqAxis(bd.getInt16(24, Endian.little)),
      lookY: _dqAxis(bd.getInt16(26, Endian.little)),
      laserX: _dqAxis(bd.getInt16(28, Endian.little)),
      laserY: _dqAxis(bd.getInt16(30, Endian.little)),
      steering: _dqAxis(bd.getInt16(32, Endian.little)),
      drivingTilt: (bd.getInt8(34) / 127.0).clamp(-1.0, 1.0),
      throttle: bytes[35] / 255.0,
      brake: bytes[36] / 255.0,
      modeIndex: modeIdx,
      hostModeRevision: rev,
      trigger: (f16 & (1 << 0)) != 0,
      action: (f16 & (1 << 1)) != 0,
      btnA: (f16 & (1 << 2)) != 0,
      btnB: (f16 & (1 << 3)) != 0,
      btnX: (f16 & (1 << 4)) != 0,
      btnY: (f16 & (1 << 5)) != 0,
      btnL: (f16 & (1 << 6)) != 0,
      btnR: (f16 & (1 << 7)) != 0,
      btnZL: (f8 & (1 << 4)) != 0,
      btnZR: (f8 & (1 << 5)) != 0,
      btnGrip: (f16 & (1 << 8)) != 0,
      stickClick: (f16 & (1 << 9)) != 0,
      recenter: (f16 & (1 << 10)) != 0,
      moveAtEdge: (f16 & (1 << 11)) != 0,
      dpadUp: (modeByte & (1 << 3)) != 0,
      dpadDown: (modeByte & (1 << 4)) != 0,
      dpadLeft: (modeByte & (1 << 5)) != 0,
      dpadRight: (modeByte & (1 << 6)) != 0,
      laserSlideActive: (f16 & (1 << 12)) != 0,
      pointerPoseReady: (f8 & (1 << 3)) != 0,
      controllerVisible: (f16 & (1 << 13)) != 0,
      drivingPaused: (f16 & (1 << 14)) != 0,
      motionAvailable: (f16 & (1 << 15)) != 0,
      passthroughActive: (f8 & (1 << 0)) != 0,
      spatialHudVisible: (f8 & (1 << 1)) != 0,
      passthroughMix: bytes[43] / 255.0,
      rangeMeters: (hasRange && rangeMm > 0) ? (rangeMm / 1000.0) : null,
    );
  }
}
