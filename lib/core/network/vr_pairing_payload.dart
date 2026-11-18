import '../../utils/constants/vr_core_constants.dart';

/// Role of a device in a VRlizate controller pairing session.
enum VrDeviceRole { parent, child }

/// Transport selected for a VRlizate pairing session.
enum VrTransportType { localSocket, bluetoothLe, wifiDirect }

/// Immutable connection invitation shared by the parent visor and child
/// controller.
class VrPairingPayload {
  static const String uriScheme = VrCoreConstants.pairingUriScheme;
  static const String uriEndpoint = VrCoreConstants.pairingUriEndpoint;

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
    _validateHost(host);
    _validatePort(port);
    _validateToken(sessionToken);
    _validateOptionalBounded(deviceName, 'deviceName', 128);
    _validateOptionalBounded(bleServiceUuid, 'bleServiceUuid', 64);

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
      VrCoreConstants.keyHost: host,
      VrCoreConstants.keyPort: port.toString(),
      VrCoreConstants.keyToken: sessionToken,
      VrCoreConstants.keyRole: role.name,
      VrCoreConstants.keyTransport: transportType.name,
    };
    if (deviceName != null) {
      query[VrCoreConstants.keyDeviceName] = deviceName!;
    }
    if (bleServiceUuid != null) {
      query[VrCoreConstants.keyBleServiceUuid] = bleServiceUuid!;
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

    final host = _requiredUriParameter(
      uri,
      VrCoreConstants.keyHost,
      maxLength: 255,
    );
    if (_unsafeHostChars.hasMatch(host) || isBlockedVrPairingHost(host)) {
      throw FormatException(
        'Invalid pairing URI parameter "host": contains unsafe or blocked host.',
        uri,
      );
    }
    final portText = _requiredUriParameter(
      uri,
      VrCoreConstants.keyPort,
      maxLength: 16,
    );
    final token = _requiredUriParameter(
      uri,
      VrCoreConstants.keyToken,
      maxLength: 256,
    );
    final roleText = _requiredUriParameter(
      uri,
      VrCoreConstants.keyRole,
      maxLength: 32,
    );
    final transportText = _requiredUriParameter(
      uri,
      VrCoreConstants.keyTransport,
      maxLength: 32,
    );
    final deviceName = _optionalUriParameter(
      uri,
      VrCoreConstants.keyDeviceName,
      maxLength: 128,
    );
    final bleServiceUuid = _optionalUriParameter(
      uri,
      VrCoreConstants.keyBleServiceUuid,
      maxLength: 64,
    );

    final port = int.tryParse(portText);
    if (port == null ||
        port < VrCoreConstants.minPort ||
        port > VrCoreConstants.maxPort) {
      throw FormatException(
        'Invalid pairing URI parameter "port": expected an integer from 1 '
        'to 65535, got "$portText".',
        uri,
      );
    }

    final role = _enumByName(
      VrDeviceRole.values,
      roleText,
      VrCoreConstants.keyRole,
      uri,
    );
    final transport = _enumByName(
      VrTransportType.values,
      transportText,
      VrCoreConstants.keyTransport,
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
    VrCoreConstants.keyHost: host,
    VrCoreConstants.keyPort: port,
    VrCoreConstants.keySessionToken: sessionToken,
    VrCoreConstants.keyRole: role.name,
    VrCoreConstants.keyTransportType: transportType.name,
    VrCoreConstants.keyDeviceName: deviceName,
    VrCoreConstants.keyBleServiceUuid: bleServiceUuid,
  };

  factory VrPairingPayload.fromJson(Map<String, dynamic> json) {
    final host = _requiredJsonString(
      json,
      VrCoreConstants.keyHost,
      maxLength: 255,
    );
    if (_unsafeHostChars.hasMatch(host) || isBlockedVrPairingHost(host)) {
      throw FormatException(
        'Invalid JSON field "host": contains unsafe or blocked host.',
        json,
      );
    }
    final port = _requiredJsonInt(json, VrCoreConstants.keyPort);
    final token = _requiredJsonString(
      json,
      VrCoreConstants.keySessionToken,
      maxLength: 256,
    );
    final roleText = _requiredJsonString(
      json,
      VrCoreConstants.keyRole,
      maxLength: 32,
    );
    final transportText = _requiredJsonString(
      json,
      VrCoreConstants.keyTransportType,
      maxLength: 32,
    );
    final deviceName = _optionalJsonString(
      json,
      VrCoreConstants.keyDeviceName,
      maxLength: 128,
    );
    final bleServiceUuid = _optionalJsonString(
      json,
      VrCoreConstants.keyBleServiceUuid,
      maxLength: 64,
    );

    if (port < VrCoreConstants.minPort || port > VrCoreConstants.maxPort) {
      throw FormatException(
        'Invalid JSON field "port": expected an integer from 1 to 65535, '
        'got "$port".',
      );
    }

    final role = _enumByName(
      VrDeviceRole.values,
      roleText,
      VrCoreConstants.keyRole,
      json,
    );
    final transport = _enumByName(
      VrTransportType.values,
      transportText,
      VrCoreConstants.keyTransportType,
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

final RegExp _disallowedPairingControlOrBidi = RegExp(
  r'[\x00-\x1F\x7F-\x9F\u0085\u061C\u200B-\u200F\u2028-\u202E\u2060\u2066-\u2069\uFEFF]',
);

final RegExp _unsafeHostChars = RegExp(r'[\s/\\@#?%\u3002\uFF0E\uFF61]');

/// Returns `true` when [rawHost] targets cloud instance metadata services,
/// unspecified/broadcast/multicast addresses, IPv6 transition tunnels (Teredo),
/// or `.invalid` domains that must never be contacted by a pairing client.
///
/// Private LAN (`192.168.*`, `10.*`, `172.16-31.*`), loopback (`127.0.0.1`,
/// `::1`, `localhost`), and mDNS (`*.local`) remain allowed for local visors.
bool isBlockedVrPairingHost(String rawHost) {
  var h = rawHost.trim().toLowerCase();
  if (h.isEmpty) return true;
  if (h.startsWith('[') && h.endsWith(']') && h.length >= 2) {
    h = h.substring(1, h.length - 1);
  }
  while (h.endsWith('.')) {
    h = h.substring(0, h.length - 1);
  }
  if (h.isEmpty) return true;

  if (h == '0.0.0.0' ||
      h == '255.255.255.255' ||
      h == '169.254.169.254' ||
      h == '100.100.100.200' ||
      h == '::' ||
      h == '0:0:0:0:0:0:0:0' ||
      h == 'fd00:ec2::254' ||
      h == 'metadata' ||
      h == 'metadata.google.internal' ||
      h == 'metadata.goog' ||
      h == 'metadata.azure.com' ||
      h == 'instance-data' ||
      h.endsWith('.metadata.google.internal') ||
      h.endsWith('.metadata.goog') ||
      h.endsWith('.invalid')) {
    return true;
  }

  // Block IPv6 multicast (ff00::/8), Teredo (2001:0000::/32), and IPv4-mapped metadata
  if (h.contains(':')) {
    if (h.startsWith('ff') ||
        h.startsWith('2001:0:') ||
        h.startsWith('2001:0000:') ||
        h.contains('169.254.169.254') ||
        h.contains('a9fe:a9fe') ||
        h.contains('100.100.100.200') ||
        h.contains('6464:64c8')) {
      return true;
    }
    return false;
  }

  // Check IPv4 octets if numeric
  final parts = h.split('.');
  if (parts.length == 4 && parts.every((p) => RegExp(r'^\d+$').hasMatch(p))) {
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return true;
    final a = octets[0]!;
    final b = octets[1]!;
    final c = octets[2]!;
    final d = octets[3]!;
    if (a == 0 || a >= 224) return true; // 0.0.0.0/8, multicast & reserved
    if (a == 169 && b == 254 && c == 169 && d == 254) return true;
    if (a == 100 && b == 100 && c == 100 && d == 200) return true;
  } else if (RegExp(r'^(?:0x[0-9a-f]+|\d+)$').hasMatch(h)) {
    // Reject single-integer / hex-encoded IPv4 SSRF bypasses (e.g. 2852039166)
    return true;
  }

  return false;
}

void _validateHost(String value) {
  _validateBounded(value, 'host', 255);
  if (_unsafeHostChars.hasMatch(value) || isBlockedVrPairingHost(value)) {
    throw ArgumentError.value(
      value,
      'host',
      'Must be a valid visor host and not a blocked metadata/multicast target.',
    );
  }
}

void _validateToken(String value) {
  _validateBounded(value, 'sessionToken', 256);
}

void _validateBounded(String value, String name, int maxLength) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  if (value.length > maxLength) {
    throw ArgumentError.value(
      value,
      name,
      'Must not exceed $maxLength characters.',
    );
  }
  if (_disallowedPairingControlOrBidi.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'Must not contain control or Bidi override characters.',
    );
  }
}

void _validateOptionalBounded(String? value, String name, int maxLength) {
  if (value != null) _validateBounded(value, name, maxLength);
}

void _validatePort(int port) {
  if (!port.isFinite || port < 1 || port > 65535) {
    throw RangeError.range(port, 1, 65535, 'port');
  }
}

String _requiredUriParameter(Uri uri, String name, {required int maxLength}) {
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
  if (value.length > maxLength ||
      _disallowedPairingControlOrBidi.hasMatch(value)) {
    throw FormatException(
      'Pairing URI parameter "$name" exceeds length or contains control chars.',
      uri,
    );
  }
  return value;
}

String? _optionalUriParameter(Uri uri, String name, {required int maxLength}) {
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
  if (value.length > maxLength ||
      _disallowedPairingControlOrBidi.hasMatch(value)) {
    throw FormatException(
      'Pairing URI parameter "$name" exceeds length or contains control chars.',
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

String _requiredJsonString(
  Map<String, dynamic> json,
  String name, {
  required int maxLength,
}) {
  final value = json[name];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'Invalid JSON field "$name": expected a non-empty string.',
      json,
    );
  }
  if (value.length > maxLength ||
      _disallowedPairingControlOrBidi.hasMatch(value)) {
    throw FormatException(
      'Invalid JSON field "$name": exceeds length or contains control chars.',
      json,
    );
  }
  return value;
}

int _requiredJsonInt(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! int || !value.isFinite) {
    throw FormatException(
      'Invalid JSON field "$name": expected an integer.',
      json,
    );
  }
  return value;
}

String? _optionalJsonString(
  Map<String, dynamic> json,
  String name, {
  required int maxLength,
}) {
  final value = json[name];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'Invalid JSON field "$name": expected a non-empty string or null.',
      json,
    );
  }
  if (value.length > maxLength ||
      _disallowedPairingControlOrBidi.hasMatch(value)) {
    throw FormatException(
      'Invalid JSON field "$name": exceeds length or contains control chars.',
      json,
    );
  }
  return value;
}
