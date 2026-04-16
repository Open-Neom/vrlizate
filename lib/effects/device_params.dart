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
}
