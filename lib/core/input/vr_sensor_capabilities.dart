import 'package:flutter/foundation.dart';

/// Platform registration of the device-motion backend, not a guarantee that
/// a particular device contains a sensor or that browser permission is granted.
///
/// sensors_plus provides Android, iOS and Web implementations. Native desktop
/// hosts keep touch/gamepad input; custom sensor streams remain usable there.
abstract final class VrSensorCapabilities {
  static bool get supportsDeviceMotion =>
      supportsDeviceMotionOn(defaultTargetPlatform, isWeb: kIsWeb);

  static bool supportsDeviceMotionOn(
    TargetPlatform platform, {
    bool isWeb = false,
  }) =>
      isWeb ||
      platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS;
}
