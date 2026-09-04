/// Role of a device in a VRlizate controller pairing session.
enum VrDeviceRole { parent, child }

/// Transport selected for a VRlizate pairing session.
enum VrTransportType { localSocket, bluetoothLe, wifiDirect }

/// Immutable connection invitation shared by the parent visor and child
/// controller.
class VrPairingPayload {
  static const String uriScheme = 'vrlizate';
  static const String uriEndpoint = 'pair';

  final String host;
  final int port;
  final String sessionToken;
  final VrDeviceRole role;
  final VrTransportType transportType;
  final String? deviceName;
  final String? bleServiceUuid;

  factory VrPairingPayload({
    required String host,
    required int port,
    required String sessionToken,
    required VrDeviceRole role,
    required VrTransportType transportType,
    String? deviceName,
    String? bleServiceUuid,
  }) {
    _validateNonEmpty(host, 'host');
    _validatePort(port);
    _validateNonEmpty(sessionToken, 'sessionToken');
    _validateOptionalNonEmpty(deviceName, 'deviceName');
    _validateOptionalNonEmpty(bleServiceUuid, 'bleServiceUuid');

    return VrPairingPayload._(
      host: host,
      port: port,
      sessionToken: sessionToken,
      role: role,
      transportType: transportType,
      deviceName: deviceName,
      bleServiceUuid: bleServiceUuid,
    );
  }

  const VrPairingPayload._({
    required this.host,
    required this.port,
    required this.sessionToken,
    required this.role,
    required this.transportType,
    this.deviceName,
    this.bleServiceUuid,
  });

  /// Encodes this invitation as a canonical `vrlizate://pair` URI.
  Uri toUri() {
    final query = <String, String>{
      'host': host,
      'port': port.toString(),
      'token': sessionToken,
      'role': role.name,
      'transport': transportType.name,
    };
    if (deviceName != null) query['deviceName'] = deviceName!;
    if (bleServiceUuid != null) {
      query['bleServiceUuid'] = bleServiceUuid!;
    }

    return Uri(scheme: uriScheme, host: uriEndpoint, queryParameters: query);
  }

  /// Parses and validates a canonical VRlizate pairing URI.
  factory VrPairingPayload.fromUri(Uri uri) {
    if (uri.scheme != uriScheme) {
      throw FormatException(
        'Invalid pairing URI scheme "${uri.scheme}"; expected "$uriScheme".',
        uri,
      );
    }
    if (!uri.hasAuthority || uri.host != uriEndpoint) {
      throw FormatException(
        'Invalid pairing URI endpoint "${uri.host}"; expected '
        '"$uriEndpoint".',
        uri,
      );
    }
    if (uri.path.isNotEmpty || uri.fragment.isNotEmpty) {
      throw FormatException(
        'Pairing URI must not contain a path or fragment.',
        uri,
      );
    }

    final host = _requiredUriParameter(uri, 'host');
    final portText = _requiredUriParameter(uri, 'port');
    final token = _requiredUriParameter(uri, 'token');
    final roleText = _requiredUriParameter(uri, 'role');
    final transportText = _requiredUriParameter(uri, 'transport');
    final deviceName = _optionalUriParameter(uri, 'deviceName');
    final bleServiceUuid = _optionalUriParameter(uri, 'bleServiceUuid');

    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      throw FormatException(
        'Invalid pairing URI parameter "port": expected an integer from 1 '
        'to 65535, got "$portText".',
        uri,
      );
    }

    final role = _enumByName(VrDeviceRole.values, roleText, 'role', uri);
    final transport = _enumByName(
      VrTransportType.values,
      transportText,
      'transport',
      uri,
    );

    return VrPairingPayload._(
      host: host,
      port: port,
      sessionToken: token,
      role: role,
      transportType: transport,
      deviceName: deviceName,
      bleServiceUuid: bleServiceUuid,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'host': host,
    'port': port,
    'sessionToken': sessionToken,
    'role': role.name,
    'transportType': transportType.name,
    'deviceName': deviceName,
    'bleServiceUuid': bleServiceUuid,
  };

  factory VrPairingPayload.fromJson(Map<String, dynamic> json) {
    final host = _requiredJsonString(json, 'host');
    final port = _requiredJsonInt(json, 'port');
    final token = _requiredJsonString(json, 'sessionToken');
    final roleText = _requiredJsonString(json, 'role');
    final transportText = _requiredJsonString(json, 'transportType');
    final deviceName = _optionalJsonString(json, 'deviceName');
    final bleServiceUuid = _optionalJsonString(json, 'bleServiceUuid');

    if (port < 1 || port > 65535) {
      throw FormatException(
        'Invalid JSON field "port": expected an integer from 1 to 65535, '
        'got "$port".',
      );
    }

    final role = _enumByName(VrDeviceRole.values, roleText, 'role', json);
    final transport = _enumByName(
      VrTransportType.values,
      transportText,
      'transportType',
      json,
    );

    return VrPairingPayload._(
      host: host,
      port: port,
      sessionToken: token,
      role: role,
      transportType: transport,
      deviceName: deviceName,
      bleServiceUuid: bleServiceUuid,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrPairingPayload &&
          host == other.host &&
          port == other.port &&
          sessionToken == other.sessionToken &&
          role == other.role &&
          transportType == other.transportType &&
          deviceName == other.deviceName &&
          bleServiceUuid == other.bleServiceUuid;

  @override
  int get hashCode => Object.hash(
    host,
    port,
    sessionToken,
    role,
    transportType,
    deviceName,
    bleServiceUuid,
  );

  @override
  String toString() =>
      'VrPairingPayload(host: $host, port: $port, role: $role, '
      'transportType: $transportType, deviceName: $deviceName)';
}

void _validateNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}

void _validateOptionalNonEmpty(String? value, String name) {
  if (value != null) _validateNonEmpty(value, name);
}

void _validatePort(int port) {
  if (port < 1 || port > 65535) {
    throw RangeError.range(port, 1, 65535, 'port');
  }
}

String _requiredUriParameter(Uri uri, String name) {
  final values = uri.queryParametersAll[name];
  if (values == null || values.length != 1) {
    final problem = values != null && values.length > 1
        ? 'must appear exactly once'
        : 'is required';
    throw FormatException('Pairing URI parameter "$name" $problem.', uri);
  }
  final value = values.single;
  if (value.trim().isEmpty) {
    throw FormatException(
      'Pairing URI parameter "$name" must not be empty.',
      uri,
    );
  }
  return value;
}

String? _optionalUriParameter(Uri uri, String name) {
  final values = uri.queryParametersAll[name];
  if (values == null) return null;
  if (values.length != 1) {
    throw FormatException(
      'Pairing URI parameter "$name" must appear at most once.',
      uri,
    );
  }
  final value = values.single;
  if (value.trim().isEmpty) {
    throw FormatException(
      'Pairing URI parameter "$name" must not be empty when present.',
      uri,
    );
  }
  return value;
}

T _enumByName<T extends Enum>(
  List<T> values,
  String name,
  String field,
  Object source,
) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException(
    'Invalid "$field" value "$name"; expected one of: '
    '${values.map((value) => value.name).join(', ')}.',
    source,
  );
}

String _requiredJsonString(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'Invalid JSON field "$name": expected a non-empty string.',
      json,
    );
  }
  return value;
}

int _requiredJsonInt(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! int) {
    throw FormatException(
      'Invalid JSON field "$name": expected an integer.',
      json,
    );
  }
  return value;
}

String? _optionalJsonString(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'Invalid JSON field "$name": expected a non-empty string or null.',
      json,
    );
  }
  return value;
}
