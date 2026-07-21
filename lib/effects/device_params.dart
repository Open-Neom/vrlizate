import 'dart:convert';
import 'dart:typed_data';

/// VR headset device parameters.
/// Different headsets have different lens properties.
class DeviceParams {
  final String vendor;
  final String model;

  /// Distance from screen to lens center in meters.
  final double screenToLensDistance;

  /// Distance between lens centers in meters.
  final double interLensDistance;

  /// Tray-to-lens distance (for phone alignment).
  final double trayToLensDistance;

  /// Distortion coefficients for polynomial correction.
  final List<double> distortionCoefficients;

  /// Field of view angles in degrees: [left, right, bottom, top].
  final List<double> fovAngles;

  const DeviceParams({
    required this.vendor,
    required this.model,
    this.screenToLensDistance = 0.042,
    this.interLensDistance = 0.064,
    this.trayToLensDistance = 0.035,
    this.distortionCoefficients = const [0.441, 0.156],
    this.fovAngles = const [40, 40, 40, 40],
  });

  double get ipd => interLensDistance;

  /// Google Cardboard V1.
  static const cardboardV1 = DeviceParams(
    vendor: 'Google',
    model: 'Cardboard V1',
    screenToLensDistance: 0.042,
    interLensDistance: 0.06,
    distortionCoefficients: [0.441, 0.156],
    fovAngles: [40, 40, 40, 40],
  );

  /// Google Cardboard V2.
  static const cardboardV2 = DeviceParams(
    vendor: 'Google',
    model: 'Cardboard V2',
    screenToLensDistance: 0.039,
    interLensDistance: 0.064,
    distortionCoefficients: [0.34, 0.55],
    fovAngles: [50, 50, 50, 50],
  );

  /// Samsung Gear VR (approximate).
  static const gearVr = DeviceParams(
    vendor: 'Samsung',
    model: 'Gear VR',
    screenToLensDistance: 0.04,
    interLensDistance: 0.063,
    distortionCoefficients: [0.215, 0.215],
    fovAngles: [50, 50, 50, 50],
  );

  /// No distortion (for testing/development).
  static const none = DeviceParams(
    vendor: 'None',
    model: 'Flat',
    screenToLensDistance: 0,
    interLensDistance: 0.064,
    distortionCoefficients: [0, 0],
    fovAngles: [45, 45, 45, 45],
  );

  /// Generic mobile VR viewer.
  static const generic = DeviceParams(
    vendor: 'Generic',
    model: 'Mobile VR',
    screenToLensDistance: 0.04,
    interLensDistance: 0.064,
    distortionCoefficients: [0.35, 0.2],
    fovAngles: [45, 45, 45, 45],
  );

  /// Decodes Google Cardboard QR configuration parameters from URI string.
  /// Decodes official Cardboard Protobuf payloads in `?p=` as well as custom query parameters.
  static DeviceParams fromCardboardQrUri(Uri uri) {
    final params = uri.queryParameters;

    // Check if official Cardboard base64 protobuf ?p= parameter is present
    if (params.containsKey('p')) {
      try {
        final rawBase64 = params['p']!.replaceAll('-', '+').replaceAll('_', '/');
        final padded = rawBase64.padRight((rawBase64.length + 3) & ~3, '=');
        final bytes = base64Decode(padded);
        return _parseProtobufCardboardParams(bytes);
      } catch (_) {
        // Fallback to query parameters if protobuf parsing fails
      }
    }

    final vendor = params['v'] ?? 'Custom';
    final model = params['m'] ?? 'VR Viewer';
    final interLens = double.tryParse(params['ipd'] ?? '') ?? 0.064;
    final screenLens = double.tryParse(params['std'] ?? '') ?? 0.042;
    final k1 = double.tryParse(params['k1'] ?? '') ?? 0.34;
    final k2 = double.tryParse(params['k2'] ?? '') ?? 0.55;

    return DeviceParams(
      vendor: vendor,
      model: model,
      interLensDistance: interLens,
      screenToLensDistance: screenLens,
      distortionCoefficients: [k1, k2],
    );
  }

  static DeviceParams _parseProtobufCardboardParams(Uint8List bytes) {
    String vendor = 'Google Cardboard';
    String model = 'Custom Viewer';
    double screenToLens = 0.042;
    double interLens = 0.064;
    double trayToLens = 0.035;
    final distortion = <double>[];

    var offset = 0;
    while (offset < bytes.length) {
      final tag = bytes[offset++];
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;

      if (wireType == 2) {
        // Length-delimited (String or submessage)
        var len = 0;
        var shift = 0;
        while (offset < bytes.length) {
          final b = bytes[offset++];
          len |= (b & 0x7F) << shift;
          if ((b & 0x80) == 0) break;
          shift += 7;
        }

        if (offset + len <= bytes.length) {
          final stringVal = utf8.decode(bytes.sublist(offset, offset + len), allowMalformed: true);
          if (fieldNumber == 1) vendor = stringVal;
          if (fieldNumber == 2) model = stringVal;
          offset += len;
        }
      } else if (wireType == 5) {
        // 32-bit float
        if (offset + 4 <= bytes.length) {
          final floatVal = ByteData.sublistView(bytes, offset, offset + 4).getFloat32(0, Endian.little);
          offset += 4;
          if (fieldNumber == 3) screenToLens = floatVal;
          if (fieldNumber == 4) interLens = floatVal;
          if (fieldNumber == 6) trayToLens = floatVal;
          if (fieldNumber == 7) distortion.add(floatVal);
        }
      } else if (wireType == 0) {
        // Varint (skip)
        while (offset < bytes.length && (bytes[offset++] & 0x80) != 0) {}
      } else {
        // Unknown wire type, terminate loop safely
        break;
      }
    }

    return DeviceParams(
      vendor: vendor.isEmpty ? 'Cardboard' : vendor,
      model: model.isEmpty ? 'Viewer' : model,
      screenToLensDistance: screenToLens,
      interLensDistance: interLens,
      trayToLensDistance: trayToLens,
      distortionCoefficients: distortion.isNotEmpty ? distortion : const [0.34, 0.55],
    );
  }
}
