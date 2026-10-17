/// Centralized constants for gaze-based dwell interaction in `vrlizate`.
///
/// Tuned for deliberate, non-rushed selection so scanning a scene does not
/// trigger accidental clicks or drags.
abstract final class VrGazeConstants {
  /// Default dwell duration in seconds required to select a fresh target.
  static const double defaultDwellDuration = 2.6;

  /// Minimum dwell duration in seconds when adaptive dwell accelerates
  /// consecutive selections of the same target.
  static const double defaultMinDwellDuration = 1.6;

  /// Initial stabilization delay in seconds when gazing at a target before
  /// the dwell progress ring begins filling.
  static const double defaultDwellActivationDelay = 0.35;

  /// Dwell acceleration factor applied to consecutive selections of the same
  /// target.
  static const double defaultDwellAcceleration = 0.8;

  /// Grace period in seconds during which a brief gaze slip preserves the
  /// accumulated dwell timer.
  static const double defaultGazeGracePeriod = 0.18;
}
