/// Centralized constants for `vrlizate` core networking, sensors, optics,
/// engine timing, and universal device tier scaling.
abstract final class VrCoreConstants {
  // ============ Controller Network & Pairing Protocol ============
  static const int controllerProtocolVersion = 1;
  static const String pairingUriScheme = 'vrlizate';
  static const String pairingUriEndpoint = 'pair';
  static const int minPort = 1;
  static const int maxPort = 65535;
  static const double defaultControlWidth = 0.18;
  static const double defaultControlHeight = 0.12;
  static const double minQuaternionLengthSquared = 1e-12;

  static const String keyId = 'id';
  static const String keyLabel = 'label';
  static const String keyKind = 'kind';
  static const String keyX = 'x';
  static const String keyY = 'y';
  static const String keyWidth = 'width';
  static const String keyHeight = 'height';
  static const String keyProtocolVersion = 'protocolVersion';
  static const String keyDeviceId = 'deviceId';
  static const String keyDeviceName = 'deviceName';
  static const String keyHandedness = 'handedness';
  static const String keyWidthMeters = 'widthMeters';
  static const String keyHeightMeters = 'heightMeters';
  static const String keyControls = 'controls';
  static const String keySequence = 'sequence';
  static const String keyTimestampUs = 'timestampUs';
  static const String keyOrientation = 'orientation';
  static const String keyAngularVelocity = 'angularVelocity';
  static const String keyAccelerometer = 'accelerometer';
  static const String keyButtons = 'buttons';
  static const String keyTouch = 'touch';
  static const String keyRange = 'range';
  static const String keyMeters = 'meters';
  static const String keySource = 'source';
  static const String keyConfidence = 'confidence';
  static const String keyType = 'type';
  static const String keyTargetId = 'targetId';
  static const String keyData = 'data';
  static const String keyActive = 'active';
  static const String keySessionToken = 'sessionToken';
  static const String keyRole = 'role';
  static const String keyProfile = 'profile';
  static const String keyFrame = 'frame';
  static const String keyEvent = 'event';
  static const String keySentTimestampUs = 'sentTimestampUs';
  static const String keyResponseTimestampUs = 'responseTimestampUs';
  static const String keyReason = 'reason';
  static const String keyCode = 'code';
  static const String keyMessage = 'message';
  static const String keyHost = 'host';
  static const String keyPort = 'port';
  static const String keyToken = 'token';
  static const String keyTransport = 'transport';
  static const String keyTransportType = 'transportType';
  static const String keyBleServiceUuid = 'bleServiceUuid';
  static const String keyWireType = r'$type';
  static const String keyWireValue = 'value';

  static const String wireTypeQuaternion = 'quaternion';
  static const String wireTypeVector2 = 'vector2';
  static const String wireTypeVector3 = 'vector3';

  static const String msgKindHello = 'hello';
  static const String msgKindReady = 'ready';
  static const String msgKindProfile = 'profile';
  static const String msgKindPose = 'pose';
  static const String msgKindInput = 'input';
  static const String msgKindPing = 'ping';
  static const String msgKindPong = 'pong';
  static const String msgKindDisconnect = 'disconnect';
  static const String msgKindError = 'error';

  // ============ Ultrasonic Gesture DSP ============
  static const int defaultUltrasonicSampleRate = 48000;
  static const double defaultUltrasonicCarrierFrequency = 19000.0;
  static const int defaultUltrasonicFftSize = 1024;
  static const double defaultUltrasonicBandwidth = 1200.0;
  static const double defaultUltrasonicPresenceThreshold = 1.8;
  static const double defaultUltrasonicDopplerThreshold = 120.0;
  static const int defaultUltrasonicCooldownMs = 350;
  static const double defaultUltrasonicNoiseFloor = 1e-9;
  static const double defaultUltrasonicToneAmplitude = 0.6;
  static const double ultrasonicCarrierLeakageGuardHz = 30.0;
  static const double ultrasonicNoiseFloorRetention = 0.995;
  static const double ultrasonicNoiseFloorUpdateRate = 0.005;

  // ============ Wi-Fi RTT & CSI Sensing ============
  static const int defaultRttWindowSeconds = 2;
  static const double defaultRttOutlierThresholdMeters = 2.0;
  static const double defaultRttSmoothing = 0.4;
  static const int minRttAnchorsForFix = 3;
  static const int maxRttGaussNewtonIterations = 12;

  static const double defaultRespirationRateBpm = 16.0;
  static const String csiKeyId = 'id';
  static const String csiKeyPx = 'px';
  static const String csiKeyPy = 'py';
  static const String csiKeyPz = 'pz';
  static const String csiKeyRespiration = 'respiration';
  static const String csiKeyIntensity = 'intensity';
  static const String csiKeyIsMoving = 'isMoving';
  static const String csiKeyTimestamp = 'timestamp';
  static const String csiKeyAmplitudes = 'amplitudes';
  static const String defaultCsiSubjectId = 'subject_alpha';

  // ============ Optics & Lens Distortion ============
  static const double defaultScreenToLensDistance = 0.042;
  static const double cardboardV2ScreenToLensDistance = 0.039;
  static const double defaultInterLensDistance = 0.064;
  static const double cardboardV1InterLensDistance = 0.06;
  static const double defaultTrayToLensDistance = 0.035;
  static const double cardboardV1K1 = 0.441;
  static const double cardboardV1K2 = 0.156;
  static const double cardboardV2K1 = 0.34;
  static const double cardboardV2K2 = 0.55;
  static const double defaultLensK1 = 0.22;
  static const double defaultLensK2 = 0.24;
  static const List<double> cardboardV1Distortion = <double>[
    cardboardV1K1,
    cardboardV1K2,
  ];
  static const List<double> cardboardV2Distortion = <double>[
    cardboardV2K1,
    cardboardV2K2,
  ];
  static const List<double> defaultLensDistortionK = <double>[
    defaultLensK1,
    defaultLensK2,
  ];
  static const int defaultDistortionMeshResolution = 40;

  // ============ VR Engine Loop & Input ============
  static const int fallbackTimerPeriodMs = 16;
  static const double maxFrameDeltaTimeSec = 0.1;
  static const double maxInputDeltaTimeSec = 0.25;
  static const double atwFallbackThresholdMs = 18.0;
  static const double defaultLookYawSpeed = 2.1;
  static const double defaultLookPitchSpeed = 1.5;
  static const double defaultDesktopLookSensitivity = 0.0035;
  static const double defaultDesktopMoveSpeed = 3.0;
  static const double defaultDesktopSprintMultiplier = 2.5;
  static const int dwellReleaseDelayMs = 100;

  // ============ Universal Ecosystem Device Tier & Auto-Scaler ============
  static const int ultraFlagshipMinRamMb = 7500;
  static const int ultraFlagshipMinCpuCores = 8;
  static const double ultraFlagshipMinRefreshHz = 90.0;

  static const int balancedMidRangeMinRamMb = 3800;
  static const int balancedMidRangeMinCpuCores = 6;

  static const double ultraRenderScaleFactor = 1.0;
  static const int ultraTargetFps = 90;
  static const int ultraMaxActiveLights = 8;
  static const int ultraMaxParticleCount = 600;
  static const int ultraSensorFusionHz = 120;

  static const double balancedRenderScaleFactor = 0.85;
  static const int balancedTargetFps = 60;
  static const int balancedMaxActiveLights = 4;
  static const int balancedMaxParticleCount = 240;
  static const int balancedSensorFusionHz = 100;

  static const double accessibleRenderScaleFactor = 0.65;
  static const int accessibleTargetFps = 60;
  static const int accessibleMaxActiveLights = 2;
  static const int accessibleMaxParticleCount = 80;
  static const int accessibleSensorFusionHz = 60;

  static const double standaloneRenderScaleFactor = 0.75;
  static const int standaloneTargetFps = 60;
  static const int standaloneMaxActiveLights = 3;
  static const int standaloneMaxParticleCount = 120;
  static const int standaloneSensorFusionHz = 90;

  static const double minRenderScaleFactor = 0.5;
  static const double maxRenderScaleFactor = 1.0;
  static const double renderScaleStepDown = 0.1;
  static const double renderScaleStepUp = 0.05;
  static const double frameBudgetOverrunRatio = 1.12;
  static const double frameBudgetHeadroomRatio = 0.72;
  static const double millisecondsPerSecond = 1000.0;
}
