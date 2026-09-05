import 'dart:convert';

import 'package:vector_math/vector_math.dart';

import '../input/vr_input_event_bus.dart';
import 'vr_pairing_payload.dart';

/// Current wire protocol understood by VRlizate remote controllers.
const int vrControllerProtocolVersion = 1;

enum VrControllerHandedness { unspecified, left, right }

enum VrControlKind { button, trigger, touchpad, stick }

enum VrRangeSource { fixed, bluetoothRssi, wifiRtt, ultraWideband, vision }

/// One visual and semantic control exposed by a remote device.
class VrControlDescriptor {
  final String id;
  final String label;
  final VrControlKind kind;

  /// Center and size in normalized portrait-screen coordinates.
  final double x;
  final double y;
  final double width;
  final double height;

  factory VrControlDescriptor({
    required String id,
    required String label,
    required VrControlKind kind,
    required double x,
    required double y,
    double width = 0.18,
    double height = 0.12,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(label, 'label');
    _requireUnit(x, 'x');
    _requireUnit(y, 'y');
    _requirePositiveUnit(width, 'width');
    _requirePositiveUnit(height, 'height');
    return VrControlDescriptor._(
      id: id,
      label: label,
      kind: kind,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  const VrControlDescriptor._({
    required this.id,
    required this.label,
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'kind': kind.name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory VrControlDescriptor.fromJson(Map<String, dynamic> json) =>
      VrControlDescriptor(
        id: _jsonString(json, 'id'),
        label: _jsonString(json, 'label'),
        kind: _jsonEnum(VrControlKind.values, json, 'kind'),
        x: _jsonDouble(json, 'x'),
        y: _jsonDouble(json, 'y'),
        width: _jsonDouble(json, 'width'),
        height: _jsonDouble(json, 'height'),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrControlDescriptor &&
          id == other.id &&
          label == other.label &&
          kind == other.kind &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(id, label, kind, x, y, width, height);
}

/// Description sent once by the child so the visor can build a controller UI.
class VrControllerProfile {
  final int protocolVersion;
  final String deviceId;
  final String deviceName;
  final VrControllerHandedness handedness;
  final double widthMeters;
  final double heightMeters;
  final List<VrControlDescriptor> controls;

  factory VrControllerProfile({
    int protocolVersion = vrControllerProtocolVersion,
    required String deviceId,
    required String deviceName,
    VrControllerHandedness handedness = VrControllerHandedness.unspecified,
    required double widthMeters,
    required double heightMeters,
    required List<VrControlDescriptor> controls,
  }) {
    if (protocolVersion <= 0) {
      throw RangeError.value(
        protocolVersion,
        'protocolVersion',
        'Must be > 0.',
      );
    }
    _requireNonEmpty(deviceId, 'deviceId');
    _requireNonEmpty(deviceName, 'deviceName');
    _requirePositive(widthMeters, 'widthMeters');
    _requirePositive(heightMeters, 'heightMeters');
    final ids = <String>{};
    for (final control in controls) {
      if (!ids.add(control.id)) {
        throw ArgumentError.value(
          control.id,
          'controls',
          'Control ids must be unique.',
        );
      }
    }
    return VrControllerProfile._(
      protocolVersion: protocolVersion,
      deviceId: deviceId,
      deviceName: deviceName,
      handedness: handedness,
      widthMeters: widthMeters,
      heightMeters: heightMeters,
      controls: List<VrControlDescriptor>.unmodifiable(controls),
    );
  }

  const VrControllerProfile._({
    required this.protocolVersion,
    required this.deviceId,
    required this.deviceName,
    required this.handedness,
    required this.widthMeters,
    required this.heightMeters,
    required this.controls,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'protocolVersion': protocolVersion,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'handedness': handedness.name,
    'widthMeters': widthMeters,
    'heightMeters': heightMeters,
    'controls': controls.map((control) => control.toJson()).toList(),
  };

  factory VrControllerProfile.fromJson(Map<String, dynamic> json) {
    final rawControls = json['controls'];
    if (rawControls is! List) {
      throw const FormatException(
        'Invalid profile field "controls": expected a list.',
      );
    }
    return VrControllerProfile(
      protocolVersion: _jsonInt(json, 'protocolVersion'),
      deviceId: _jsonString(json, 'deviceId'),
      deviceName: _jsonString(json, 'deviceName'),
      handedness: _jsonEnum(VrControllerHandedness.values, json, 'handedness'),
      widthMeters: _jsonDouble(json, 'widthMeters'),
      heightMeters: _jsonDouble(json, 'heightMeters'),
      controls: rawControls
          .map(
            (value) =>
                VrControlDescriptor.fromJson(_jsonMapValue(value, 'controls')),
          )
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrControllerProfile &&
          protocolVersion == other.protocolVersion &&
          deviceId == other.deviceId &&
          deviceName == other.deviceName &&
          handedness == other.handedness &&
          widthMeters == other.widthMeters &&
          heightMeters == other.heightMeters &&
          _listEquals(controls, other.controls);

  @override
  int get hashCode => Object.hash(
    protocolVersion,
    deviceId,
    deviceName,
    handedness,
    widthMeters,
    heightMeters,
    Object.hashAll(controls),
  );
}

/// Immutable high-frequency sample sent by the child controller.
///
/// Quaternion/vector components are stored as scalars so callers cannot mutate
/// a frame after it has crossed an asynchronous transport boundary.
class VrRemotePoseFrame {
  final int sequence;
  final int senderTimestampMicroseconds;
  final double qx;
  final double qy;
  final double qz;
  final double qw;
  final double angularVelocityX;
  final double angularVelocityY;
  final double angularVelocityZ;
  final double accelerometerX;
  final double accelerometerY;
  final double accelerometerZ;
  final int buttonsBitset;
  final double? touchX;
  final double? touchY;
  final double? rangeMeters;
  final VrRangeSource? rangeSource;
  final double? rangeConfidence;

  factory VrRemotePoseFrame({
    required int sequence,
    required int senderTimestampMicroseconds,
    required Quaternion orientation,
    Vector3? angularVelocity,
    Vector3? accelerometer,
    int buttonsBitset = 0,
    double? touchX,
    double? touchY,
    double? rangeMeters,
    VrRangeSource? rangeSource,
    double? rangeConfidence,
  }) {
    if (sequence < 0) {
      throw RangeError.value(sequence, 'sequence', 'Must not be negative.');
    }
    if (senderTimestampMicroseconds < 0) {
      throw RangeError.value(
        senderTimestampMicroseconds,
        'senderTimestampMicroseconds',
        'Must not be negative.',
      );
    }
    if (buttonsBitset < 0) {
      throw RangeError.value(
        buttonsBitset,
        'buttonsBitset',
        'Must not be negative.',
      );
    }
    final orientationLength2 = orientation.length2;
    if (!orientationLength2.isFinite || orientationLength2 <= 1e-12) {
      throw ArgumentError.value(
        orientation,
        'orientation',
        'Must be a finite non-zero quaternion.',
      );
    }
    final normalized = orientation.normalized();
    final velocity = angularVelocity ?? Vector3.zero();
    if (!velocity.x.isFinite || !velocity.y.isFinite || !velocity.z.isFinite) {
      throw ArgumentError.value(
        velocity,
        'angularVelocity',
        'Components must be finite.',
      );
    }
    final acceleration = accelerometer ?? Vector3.zero();
    if (!acceleration.x.isFinite ||
        !acceleration.y.isFinite ||
        !acceleration.z.isFinite) {
      throw ArgumentError.value(
        acceleration,
        'accelerometer',
        'Components must be finite.',
      );
    }
    if ((touchX == null) != (touchY == null)) {
      throw ArgumentError('touchX and touchY must both be present or absent.');
    }
    if (touchX != null) {
      _requireUnit(touchX, 'touchX');
      _requireUnit(touchY!, 'touchY');
    }
    if (rangeMeters != null) _requirePositive(rangeMeters, 'rangeMeters');
    if ((rangeMeters == null) != (rangeSource == null)) {
      throw ArgumentError(
        'rangeMeters and rangeSource must both be present or absent.',
      );
    }
    if (rangeConfidence != null) {
      if (rangeMeters == null) {
        throw ArgumentError('rangeConfidence requires rangeMeters.');
      }
      _requireUnit(rangeConfidence, 'rangeConfidence');
    }
    return VrRemotePoseFrame._(
      sequence: sequence,
      senderTimestampMicroseconds: senderTimestampMicroseconds,
      qx: normalized.x,
      qy: normalized.y,
      qz: normalized.z,
      qw: normalized.w,
      angularVelocityX: velocity.x,
      angularVelocityY: velocity.y,
      angularVelocityZ: velocity.z,
      accelerometerX: acceleration.x,
      accelerometerY: acceleration.y,
      accelerometerZ: acceleration.z,
      buttonsBitset: buttonsBitset,
      touchX: touchX,
      touchY: touchY,
      rangeMeters: rangeMeters,
      rangeSource: rangeSource,
      rangeConfidence: rangeConfidence,
    );
  }

  const VrRemotePoseFrame._({
    required this.sequence,
    required this.senderTimestampMicroseconds,
    required this.qx,
    required this.qy,
    required this.qz,
    required this.qw,
    required this.angularVelocityX,
    required this.angularVelocityY,
    required this.angularVelocityZ,
    required this.accelerometerX,
    required this.accelerometerY,
    required this.accelerometerZ,
    required this.buttonsBitset,
    this.touchX,
    this.touchY,
    this.rangeMeters,
    this.rangeSource,
    this.rangeConfidence,
  });

  Quaternion get orientation => Quaternion(qx, qy, qz, qw);

  Vector3 get angularVelocity =>
      Vector3(angularVelocityX, angularVelocityY, angularVelocityZ);

  /// Raw accelerometer sample after screen-axis normalization, including gravity.
  Vector3 get accelerometer =>
      Vector3(accelerometerX, accelerometerY, accelerometerZ);

  void copyOrientationTo(Quaternion target) => target.setValues(qx, qy, qz, qw);

  void copyAngularVelocityTo(Vector3 target) =>
      target.setValues(angularVelocityX, angularVelocityY, angularVelocityZ);

  void copyAccelerometerTo(Vector3 target) =>
      target.setValues(accelerometerX, accelerometerY, accelerometerZ);

  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'timestampUs': senderTimestampMicroseconds,
    'orientation': <double>[qx, qy, qz, qw],
    'angularVelocity': <double>[
      angularVelocityX,
      angularVelocityY,
      angularVelocityZ,
    ],
    'accelerometer': <double>[accelerometerX, accelerometerY, accelerometerZ],
    'buttons': buttonsBitset,
    if (touchX != null) 'touch': <double>[touchX!, touchY!],
    if (rangeMeters != null)
      'range': <String, Object?>{
        'meters': rangeMeters,
        'source': rangeSource!.name,
        if (rangeConfidence != null) 'confidence': rangeConfidence,
      },
  };

  factory VrRemotePoseFrame.fromJson(Map<String, dynamic> json) {
    final orientation = _jsonNumberList(json, 'orientation', 4);
    final velocity = _jsonNumberList(json, 'angularVelocity', 3);
    final acceleration = json['accelerometer'] == null
        ? const <double>[0, 0, 0]
        : _jsonNumberList(json, 'accelerometer', 3);
    final touch = json['touch'] == null
        ? null
        : _jsonNumberList(json, 'touch', 2);
    final range = json['range'] == null
        ? null
        : _jsonMapValue(json['range'], 'range');
    return VrRemotePoseFrame(
      sequence: _jsonInt(json, 'sequence'),
      senderTimestampMicroseconds: _jsonInt(json, 'timestampUs'),
      orientation: Quaternion(
        orientation[0],
        orientation[1],
        orientation[2],
        orientation[3],
      ),
      angularVelocity: Vector3(velocity[0], velocity[1], velocity[2]),
      accelerometer: Vector3(acceleration[0], acceleration[1], acceleration[2]),
      buttonsBitset: _jsonInt(json, 'buttons'),
      touchX: touch?[0],
      touchY: touch?[1],
      rangeMeters: range == null ? null : _jsonDouble(range, 'meters'),
      rangeSource: range == null
          ? null
          : _jsonEnum(VrRangeSource.values, range, 'source'),
      rangeConfidence: range == null || range['confidence'] == null
          ? null
          : _jsonDouble(range, 'confidence'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrRemotePoseFrame &&
          sequence == other.sequence &&
          senderTimestampMicroseconds == other.senderTimestampMicroseconds &&
          qx == other.qx &&
          qy == other.qy &&
          qz == other.qz &&
          qw == other.qw &&
          angularVelocityX == other.angularVelocityX &&
          angularVelocityY == other.angularVelocityY &&
          angularVelocityZ == other.angularVelocityZ &&
          accelerometerX == other.accelerometerX &&
          accelerometerY == other.accelerometerY &&
          accelerometerZ == other.accelerometerZ &&
          buttonsBitset == other.buttonsBitset &&
          touchX == other.touchX &&
          touchY == other.touchY &&
          rangeMeters == other.rangeMeters &&
          rangeSource == other.rangeSource &&
          rangeConfidence == other.rangeConfidence;

  @override
  int get hashCode => Object.hash(
    sequence,
    senderTimestampMicroseconds,
    qx,
    qy,
    qz,
    qw,
    angularVelocityX,
    angularVelocityY,
    angularVelocityZ,
    accelerometerX,
    accelerometerY,
    accelerometerZ,
    buttonsBitset,
    touchX,
    touchY,
    rangeMeters,
    rangeSource,
    rangeConfidence,
  );
}

/// Immutable copy of a potentially pooled [VrInputEvent].
class VrInputEventSnapshot {
  final VrInputType type;
  final VrInputSource source;
  final String? targetId;
  final Map<String, dynamic>? data;
  final bool active;
  final int timestampMicrosecondsSinceEpoch;

  VrInputEventSnapshot._({
    required this.type,
    required this.source,
    required this.targetId,
    required this.data,
    required this.active,
    required this.timestampMicrosecondsSinceEpoch,
  });

  /// Copies every payload value synchronously before an async send can retain it.
  factory VrInputEventSnapshot.fromEvent(VrInputEvent event) {
    final wireData = _toWireValue(event.data);
    return VrInputEventSnapshot._(
      type: event.type,
      source: event.source,
      targetId: event.targetId,
      data: wireData == null
          ? null
          : _fromWireValue(wireData) as Map<String, dynamic>,
      active: event.active,
      timestampMicrosecondsSinceEpoch: event.timestampMicrosecondsSinceEpoch,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.name,
    'source': source.name,
    'targetId': targetId,
    'data': _toWireValue(data),
    'active': active,
    'timestampUs': timestampMicrosecondsSinceEpoch,
  };

  factory VrInputEventSnapshot.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final decodedData = _fromWireValue(rawData);
    if (decodedData != null && decodedData is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid input field "data": expected an object.',
      );
    }
    final targetId = json['targetId'];
    if (targetId != null && targetId is! String) {
      throw const FormatException(
        'Invalid input field "targetId": expected a string.',
      );
    }
    final active = json['active'];
    if (active is! bool) {
      throw const FormatException(
        'Invalid input field "active": expected a boolean.',
      );
    }
    return VrInputEventSnapshot._(
      type: _jsonEnum(VrInputType.values, json, 'type'),
      source: _jsonEnum(VrInputSource.values, json, 'source'),
      targetId: targetId as String?,
      data: decodedData as Map<String, dynamic>?,
      active: active,
      timestampMicrosecondsSinceEpoch: _jsonInt(json, 'timestampUs'),
    );
  }

  VrInputEvent toEvent() => VrInputEvent(
    type: type,
    source: source,
    targetId: targetId,
    data: data,
    active: active,
    timestamp: DateTime.fromMicrosecondsSinceEpoch(
      timestampMicrosecondsSinceEpoch,
    ),
  );
}

sealed class VrControllerMessage {
  const VrControllerMessage();

  String get kind;
  Map<String, Object?> toJson();

  static VrControllerMessage fromJson(Map<String, dynamic> json) {
    final kind = _jsonString(json, 'kind');
    return switch (kind) {
      'hello' => VrHelloMessage.fromJson(json),
      'ready' => VrReadyMessage.fromJson(json),
      'profile' => VrProfileMessage.fromJson(json),
      'pose' => VrPoseMessage.fromJson(json),
      'input' => VrInputMessage.fromJson(json),
      'ping' => VrPingMessage.fromJson(json),
      'pong' => VrPongMessage.fromJson(json),
      'disconnect' => VrDisconnectMessage.fromJson(json),
      'error' => VrErrorMessage.fromJson(json),
      _ => throw FormatException('Unknown controller message kind "$kind".'),
    };
  }
}

final class VrHelloMessage extends VrControllerMessage {
  final int protocolVersion;
  final String sessionToken;
  final VrDeviceRole role;
  final String? deviceName;

  VrHelloMessage({
    this.protocolVersion = vrControllerProtocolVersion,
    required this.sessionToken,
    required this.role,
    this.deviceName,
  });

  @override
  String get kind => 'hello';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'protocolVersion': protocolVersion,
    'sessionToken': sessionToken,
    'role': role.name,
    'deviceName': deviceName,
  };

  factory VrHelloMessage.fromJson(Map<String, dynamic> json) => VrHelloMessage(
    protocolVersion: _jsonInt(json, 'protocolVersion'),
    sessionToken: _jsonString(json, 'sessionToken'),
    role: _jsonEnum(VrDeviceRole.values, json, 'role'),
    deviceName: _jsonOptionalString(json, 'deviceName'),
  );
}

final class VrReadyMessage extends VrControllerMessage {
  final int protocolVersion;

  const VrReadyMessage({this.protocolVersion = vrControllerProtocolVersion});

  @override
  String get kind => 'ready';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'protocolVersion': protocolVersion,
  };

  factory VrReadyMessage.fromJson(Map<String, dynamic> json) =>
      VrReadyMessage(protocolVersion: _jsonInt(json, 'protocolVersion'));
}

final class VrProfileMessage extends VrControllerMessage {
  final VrControllerProfile profile;
  const VrProfileMessage(this.profile);

  @override
  String get kind => 'profile';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'profile': profile.toJson(),
  };

  factory VrProfileMessage.fromJson(Map<String, dynamic> json) =>
      VrProfileMessage(VrControllerProfile.fromJson(_jsonMap(json, 'profile')));
}

final class VrPoseMessage extends VrControllerMessage {
  final VrRemotePoseFrame frame;
  const VrPoseMessage(this.frame);

  @override
  String get kind => 'pose';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'frame': frame.toJson(),
  };

  factory VrPoseMessage.fromJson(Map<String, dynamic> json) =>
      VrPoseMessage(VrRemotePoseFrame.fromJson(_jsonMap(json, 'frame')));
}

final class VrInputMessage extends VrControllerMessage {
  final VrInputEventSnapshot event;
  VrInputMessage(this.event);

  @override
  String get kind => 'input';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'event': event.toJson(),
  };

  factory VrInputMessage.fromJson(Map<String, dynamic> json) =>
      VrInputMessage(VrInputEventSnapshot.fromJson(_jsonMap(json, 'event')));
}

final class VrPingMessage extends VrControllerMessage {
  final int id;
  final int sentTimestampMicroseconds;
  const VrPingMessage({
    required this.id,
    required this.sentTimestampMicroseconds,
  });

  @override
  String get kind => 'ping';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'id': id,
    'sentTimestampUs': sentTimestampMicroseconds,
  };

  factory VrPingMessage.fromJson(Map<String, dynamic> json) => VrPingMessage(
    id: _jsonInt(json, 'id'),
    sentTimestampMicroseconds: _jsonInt(json, 'sentTimestampUs'),
  );
}

final class VrPongMessage extends VrControllerMessage {
  final int id;
  final int sentTimestampMicroseconds;
  final int responseTimestampMicroseconds;
  const VrPongMessage({
    required this.id,
    required this.sentTimestampMicroseconds,
    required this.responseTimestampMicroseconds,
  });

  @override
  String get kind => 'pong';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'id': id,
    'sentTimestampUs': sentTimestampMicroseconds,
    'responseTimestampUs': responseTimestampMicroseconds,
  };

  factory VrPongMessage.fromJson(Map<String, dynamic> json) => VrPongMessage(
    id: _jsonInt(json, 'id'),
    sentTimestampMicroseconds: _jsonInt(json, 'sentTimestampUs'),
    responseTimestampMicroseconds: _jsonInt(json, 'responseTimestampUs'),
  );
}

final class VrDisconnectMessage extends VrControllerMessage {
  final String? reason;
  const VrDisconnectMessage({this.reason});

  @override
  String get kind => 'disconnect';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'reason': reason,
  };

  factory VrDisconnectMessage.fromJson(Map<String, dynamic> json) =>
      VrDisconnectMessage(reason: _jsonOptionalString(json, 'reason'));
}

final class VrErrorMessage extends VrControllerMessage {
  final String code;
  final String message;
  VrErrorMessage({required this.code, required this.message});

  @override
  String get kind => 'error';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'code': code,
    'message': message,
  };

  factory VrErrorMessage.fromJson(Map<String, dynamic> json) => VrErrorMessage(
    code: _jsonString(json, 'code'),
    message: _jsonString(json, 'message'),
  );
}

/// Newline-friendly JSON codec used by the reference socket transport.
class VrControllerMessageCodec {
  const VrControllerMessageCodec();

  String encode(VrControllerMessage message) => jsonEncode(message.toJson());

  VrControllerMessage decode(String encoded) {
    final value = jsonDecode(encoded);
    if (value is! Map) {
      throw const FormatException('Controller message must be a JSON object.');
    }
    return VrControllerMessage.fromJson(
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

Object? _toWireValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Quaternion) {
    return <String, Object?>{
      r'$type': 'quaternion',
      'value': <double>[value.x, value.y, value.z, value.w],
    };
  }
  if (value is Vector2) {
    return <String, Object?>{
      r'$type': 'vector2',
      'value': <double>[value.x, value.y],
    };
  }
  if (value is Vector3) {
    return <String, Object?>{
      r'$type': 'vector3',
      'value': <double>[value.x, value.y, value.z],
    };
  }
  if (value is List) return value.map(_toWireValue).toList(growable: false);
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError.value(
          entry.key,
          'data',
          'Map keys must be strings.',
        );
      }
      result[entry.key as String] = _toWireValue(entry.value);
    }
    return result;
  }
  throw ArgumentError.value(
    value,
    'data',
    'Unsupported wire payload type ${value.runtimeType}.',
  );
}

Object? _fromWireValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is List) return value.map(_fromWireValue).toList(growable: false);
  if (value is Map) {
    final map = value.map((key, value) => MapEntry(key.toString(), value));
    final type = map[r'$type'];
    if (type != null) {
      final raw = map['value'];
      if (raw is! List || !raw.every((item) => item is num)) {
        throw FormatException('Invalid typed wire value for "$type".');
      }
      final numbers = raw.map((item) => (item as num).toDouble()).toList();
      return switch (type) {
        'quaternion' when numbers.length == 4 => Quaternion(
          numbers[0],
          numbers[1],
          numbers[2],
          numbers[3],
        ),
        'vector2' when numbers.length == 2 => Vector2(numbers[0], numbers[1]),
        'vector3' when numbers.length == 3 => Vector3(
          numbers[0],
          numbers[1],
          numbers[2],
        ),
        _ => throw FormatException(
          'Unknown or invalid typed wire value "$type".',
        ),
      };
    }
    return map.map((key, value) => MapEntry(key, _fromWireValue(value)));
  }
  throw FormatException('Unsupported decoded wire value ${value.runtimeType}.');
}

Map<String, dynamic> _jsonMap(Map<String, dynamic> json, String name) =>
    _jsonMapValue(json[name], name);

Map<String, dynamic> _jsonMapValue(Object? value, String name) {
  if (value is! Map) {
    throw FormatException('Invalid field "$name": expected an object.');
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String _jsonString(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'Invalid field "$name": expected a non-empty string.',
    );
  }
  return value;
}

String? _jsonOptionalString(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'Invalid field "$name": expected a non-empty string.',
    );
  }
  return value;
}

int _jsonInt(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! int) {
    throw FormatException('Invalid field "$name": expected an integer.');
  }
  return value;
}

double _jsonDouble(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! num || !value.isFinite) {
    throw FormatException('Invalid field "$name": expected a finite number.');
  }
  return value.toDouble();
}

List<double> _jsonNumberList(
  Map<String, dynamic> json,
  String name,
  int length,
) {
  final value = json[name];
  if (value is! List ||
      value.length != length ||
      !value.every((v) => v is num)) {
    throw FormatException(
      'Invalid field "$name": expected $length numeric components.',
    );
  }
  final numbers = value.map((v) => (v as num).toDouble()).toList();
  if (numbers.any((number) => !number.isFinite)) {
    throw FormatException('Invalid field "$name": components must be finite.');
  }
  return numbers;
}

T _jsonEnum<T extends Enum>(
  List<T> values,
  Map<String, dynamic> json,
  String name,
) {
  final text = _jsonString(json, name);
  for (final value in values) {
    if (value.name == text) return value;
  }
  throw FormatException(
    'Invalid field "$name" value "$text"; expected one of: '
    '${values.map((value) => value.name).join(', ')}.',
  );
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}

void _requirePositive(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw RangeError.value(
      value,
      name,
      'Must be finite and greater than zero.',
    );
  }
}

void _requireUnit(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw RangeError.range(value, 0, 1, name);
  }
}

void _requirePositiveUnit(double value, String name) {
  if (!value.isFinite || value <= 0 || value > 1) {
    throw ArgumentError.value(value, name, 'Must be finite, > 0, and <= 1.');
  }
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
