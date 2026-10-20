/// Hardware capability classification for the VRlizate universal ecosystem
/// ("un nuevo ecosistema virtual al alcance de todos").
///
/// Ensures smooth stereoscopic VR and spatial computing across everything from
/// entry-level smartphones to high-refresh-rate flagships, as well as single-phone
/// visor-only standalone setups.
enum VrDeviceCapabilityTier {
  /// High-end smartphone (8+ GB RAM, 8+ cores, 90–120 Hz display) with paired
  /// second phone controller and full tri-camera tracking.
  ultraFlagship,

  /// Mainstream smartphone (4–6 GB RAM, 6–8 cores, 60 Hz display) with paired
  /// second phone controller.
  balancedMidRange,

  /// Entry-level / budget smartphone (<4 GB RAM or <=4 cores) with aggressive
  /// FSR upscaling and reduced lighting/particle budgets to guarantee 60 FPS.
  accessibleEntryLevel,

  /// Single-phone visor-only configuration where one smartphone handles both
  /// stereoscopic rendering and onboard camera/gaze/temple-tap sensing.
  singlePhoneStandalone,
}
