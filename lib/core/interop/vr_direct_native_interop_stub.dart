import 'vr_direct_native_interop.dart';

final VrDirectCoreMotion directCoreMotionInstance = _StubDirectCoreMotion();
final VrDirectDeviceBridge directDeviceBridgeInstance =
    _StubDirectDeviceBridge();

final class _StubDirectCoreMotion implements VrDirectCoreMotion {
  @override
  bool get isSupported => false;

  @override
  bool get isDeviceMotionAvailable => false;

  @override
  bool startUpdates({double intervalSeconds = 0.01}) => false;

  @override
  void stopUpdates() {}

  @override
  VrDirectMotionSample? readSampleSync() => null;
}

final class _StubDirectDeviceBridge implements VrDirectDeviceBridge {
  @override
  bool get isAvailable => false;

  @override
  int? readThermalStatusSync() => null;

  @override
  Map<String, Object?>? readDeviceCapabilitiesSync() => null;

  @override
  int? detachAndroidSafReadOnlyFdSync(String contentUri) => null;

  @override
  ({int javaVmAddress, int appContextAddress})? androidOpenXrHandlesSync() =>
      null;
}
