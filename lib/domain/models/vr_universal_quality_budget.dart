import '../../utils/constants/vr_core_constants.dart';
import '../../utils/enums/vr_device_capability_tier.dart';

/// Immutable rendering, lighting, particle, and sensor-fusion quality budget
/// computed for a device in the VRlizate universal ecosystem.
final class VrUniversalQualityBudget {
  final VrDeviceCapabilityTier tier;
  final double renderScaleFactor;
  final int targetFps;
  final int maxActiveLights;
  final int maxParticleCount;
  final bool enablePostProcessing;
  final bool enableFullTriCameraCv;
  final int sensorFusionHz;
  final String label;

  const VrUniversalQualityBudget({
    required this.tier,
    required this.renderScaleFactor,
    required this.targetFps,
    required this.maxActiveLights,
    required this.maxParticleCount,
    required this.enablePostProcessing,
    required this.enableFullTriCameraCv,
    required this.sensorFusionHz,
    required this.label,
  });

  /// Target frame time budget in milliseconds (`1000 / targetFps`).
  double get frameBudgetMs =>
      VrCoreConstants.millisecondsPerSecond / targetFps;

  VrUniversalQualityBudget copyWith({
    VrDeviceCapabilityTier? tier,
    double? renderScaleFactor,
    int? targetFps,
    int? maxActiveLights,
    int? maxParticleCount,
    bool? enablePostProcessing,
    bool? enableFullTriCameraCv,
    int? sensorFusionHz,
    String? label,
  }) => VrUniversalQualityBudget(
    tier: tier ?? this.tier,
    renderScaleFactor: renderScaleFactor ?? this.renderScaleFactor,
    targetFps: targetFps ?? this.targetFps,
    maxActiveLights: maxActiveLights ?? this.maxActiveLights,
    maxParticleCount: maxParticleCount ?? this.maxParticleCount,
    enablePostProcessing: enablePostProcessing ?? this.enablePostProcessing,
    enableFullTriCameraCv: enableFullTriCameraCv ?? this.enableFullTriCameraCv,
    sensorFusionHz: sensorFusionHz ?? this.sensorFusionHz,
    label: label ?? this.label,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrUniversalQualityBudget &&
          tier == other.tier &&
          renderScaleFactor == other.renderScaleFactor &&
          targetFps == other.targetFps &&
          maxActiveLights == other.maxActiveLights &&
          maxParticleCount == other.maxParticleCount &&
          enablePostProcessing == other.enablePostProcessing &&
          enableFullTriCameraCv == other.enableFullTriCameraCv &&
          sensorFusionHz == other.sensorFusionHz &&
          label == other.label;

  @override
  int get hashCode => Object.hash(
    tier,
    renderScaleFactor,
    targetFps,
    maxActiveLights,
    maxParticleCount,
    enablePostProcessing,
    enableFullTriCameraCv,
    sensorFusionHz,
    label,
  );

  @override
  String toString() =>
      'VrUniversalQualityBudget(tier: $tier, scale: $renderScaleFactor, '
      'targetFps: $targetFps, lights: $maxActiveLights, '
      'particles: $maxParticleCount)';
}
