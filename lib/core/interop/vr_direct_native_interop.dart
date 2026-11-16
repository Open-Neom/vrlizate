import 'vr_direct_native_interop_stub.dart'
    if (dart.library.ffi) 'vr_direct_native_interop_io.dart'
    as impl;

/// Synchronous, zero-serialization 6DoF motion sample read directly from native
/// sensor memory (`CoreMotion` `CMDeviceMotion` on iOS/macOS).
final class VrDirectMotionSample {
  const VrDirectMotionSample({
    required this.rx,
    required this.ry,
    required this.rz,
    required this.qx,
    required this.qy,
    required this.qz,
    required this.qw,
    required this.timestampMicros,
  });

  /// Bias-removed angular velocity in device axes (`rad/s`).
  final double rx;
  final double ry;
  final double rz;

  /// Fused 3D attitude quaternion `(x, y, z, w)`.
  final double qx;
  final double qy;
  final double qz;
  final double qw;

  /// Monotonic hardware sample timestamp in microseconds.
  final int timestampMicros;
}

/// Direct Objective-C FFI bridge to Apple `CoreMotion` (`CMMotionManager`),
/// bypassing `MethodChannel` / `EventChannel` serialization and UI-thread
/// queuing so `StereoSceneView` and `VrCoreMotionGyroscope` can read fused
/// rotation rate and attitude synchronously on the render tick.
abstract interface class VrDirectCoreMotion {
  static VrDirectCoreMotion get shared => impl.directCoreMotionInstance;

  /// Whether the current OS exposes `CoreMotion.framework` (`CMMotionManager`).
  bool get isSupported;

  /// Whether fused `CMDeviceMotion` (gyroscope + accelerometer) hardware exists.
  bool get isDeviceMotionAvailable;

  /// Starts hardware `CMDeviceMotion` updates at [intervalSeconds] (default 100 Hz).
  bool startUpdates({double intervalSeconds = 0.01});

  /// Stops active `CMDeviceMotion` updates.
  void stopUpdates();

  /// Reads the latest fused `CMDeviceMotion` sample synchronously in `< 1 µs`
  /// without crossing any `MethodChannel` or message codec.
  VrDirectMotionSample? readSampleSync();
}

/// Direct Native Interop (`FFIgen` Objective-C + Android JNI C-ABI) bridge for
/// VRlizate SDK packages.
///
/// Eliminates the need for host-app Kotlin/Swift `MethodChannel` glue across:
/// - Device hardware & display refresh-rate profiling (`VrDeviceProfiler`,
///   `VrBlePeerCapabilities`, `VrDisplayPostureGate`),
/// - Real-time thermal throttling queries (`PowerManager.getCurrentThermalStatus`
///   on Android and `NSProcessInfo.thermalState` on iOS/macOS),
/// - Zero-unpack Android Storage Access Framework (`ContentResolver.openFileDescriptor`
///   `detachFd`) for `.vrlz` streaming (`vrlizate_apps`),
/// - Native `JavaVM*` and `Application` context handles for OpenXR (`vrlizate_scene`).
abstract interface class VrDirectDeviceBridge {
  static VrDirectDeviceBridge get instance => impl.directDeviceBridgeInstance;

  /// True when direct native FFI / JNI interop is active on this platform.
  bool get isAvailable;

  /// Synchronously reads current OS thermal severity (`0..6`, where `0` = nominal,
  /// `1` = light/fair, `2` = moderate, `3` = severe/serious, `4+` = critical)
  /// in sub-microsecond FFI/JNI time, or `null` when unsupported.
  int? readThermalStatusSync();

  /// Synchronously reads hardware, RAM, display modes, posture metrics, and
  /// radio capabilities in the exact schema consumed by `VrDeviceCapabilities`
  /// and `VrBlePeerCapabilities`, without any host `MethodChannel`.
  Map<String, Object?>? readDeviceCapabilitiesSync();

  /// Synchronously opens an Android `content://` SAF URI via JNI
  /// (`ContentResolver.openFileDescriptor(uri, "r").detachFd()`) and returns the
  /// detached read-only POSIX file descriptor, or `null` on non-Android / error.
  int? detachAndroidSafReadOnlyFdSync(String contentUri);

  /// Returns raw `(JavaVM*, jobject globalApplicationContext)` addresses on
  /// Android for direct native OpenXR loader initialization (`xrInitializeLoaderKHR`).
  ({int javaVmAddress, int appContextAddress})? androidOpenXrHandlesSync();
}
