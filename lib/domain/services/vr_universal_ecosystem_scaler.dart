import 'dart:math' as math;

import '../../utils/constants/vr_core_constants.dart';
import '../../utils/constants/vr_core_translation_constants.dart';
import '../../utils/enums/vr_device_capability_tier.dart';
import '../models/vr_universal_quality_budget.dart';

/// Classifies smartphone hardware and dynamically scales rendering, lighting,
/// and sensor-fusion budgets so VRlizate ("un nuevo ecosistema virtual al
/// alcance de todos") runs smoothly on any device from an entry-level phone
/// to a high-refresh flagship.
final class VrUniversalEcosystemScaler {
  const VrUniversalEcosystemScaler();

  /// Classifies a smartphone into a [VrDeviceCapabilityTier] based on RAM,
  /// CPU core count, display refresh rate, and whether a second phone is paired
  /// as a dedicated controller + dual-camera sensor unit.
  VrDeviceCapabilityTier classifyDevice({
    required int ramMegabytes,
    required int cpuCores,
    required double displayRefreshHz,
    bool hasPairedSecondPhone = true,
  }) => classifyFromSpecs(
    ramMegabytes,
    cpuCores,
    displayRefreshHz,
    hasPairedSecondPhone,
  );

  /// Positional helper that classifies hardware into a [VrDeviceCapabilityTier].
  VrDeviceCapabilityTier classifyFromSpecs(
    int ramMegabytes,
    int cpuCores,
    double displayRefreshHz,
    bool hasPairedSecondPhone,
  ) {
    if (!hasPairedSecondPhone) {
      return VrDeviceCapabilityTier.singlePhoneStandalone;
    }
    if (ramMegabytes >= VrCoreConstants.ultraFlagshipMinRamMb &&
        cpuCores >= VrCoreConstants.ultraFlagshipMinCpuCores &&
        displayRefreshHz >= VrCoreConstants.ultraFlagshipMinRefreshHz) {
      return VrDeviceCapabilityTier.ultraFlagship;
    }
    if (ramMegabytes >= VrCoreConstants.balancedMidRangeMinRamMb &&
        cpuCores >= VrCoreConstants.balancedMidRangeMinCpuCores) {
      return VrDeviceCapabilityTier.balancedMidRange;
    }
    return VrDeviceCapabilityTier.accessibleEntryLevel;
  }

  /// Returns the baseline [VrUniversalQualityBudget] for [tier].
  VrUniversalQualityBudget budgetForTier(VrDeviceCapabilityTier tier) =>
      switch (tier) {
        VrDeviceCapabilityTier.ultraFlagship => const VrUniversalQualityBudget(
          tier: VrDeviceCapabilityTier.ultraFlagship,
          renderScaleFactor: VrCoreConstants.ultraRenderScaleFactor,
          targetFps: VrCoreConstants.ultraTargetFps,
          maxActiveLights: VrCoreConstants.ultraMaxActiveLights,
          maxParticleCount: VrCoreConstants.ultraMaxParticleCount,
          enablePostProcessing: true,
          enableFullTriCameraCv: true,
          sensorFusionHz: VrCoreConstants.ultraSensorFusionHz,
          label: VrCoreTranslationConstants.tierUltraFlagshipLabel,
        ),
        VrDeviceCapabilityTier.balancedMidRange =>
          const VrUniversalQualityBudget(
            tier: VrDeviceCapabilityTier.balancedMidRange,
            renderScaleFactor: VrCoreConstants.balancedRenderScaleFactor,
            targetFps: VrCoreConstants.balancedTargetFps,
            maxActiveLights: VrCoreConstants.balancedMaxActiveLights,
            maxParticleCount: VrCoreConstants.balancedMaxParticleCount,
            enablePostProcessing: true,
            enableFullTriCameraCv: true,
            sensorFusionHz: VrCoreConstants.balancedSensorFusionHz,
            label: VrCoreTranslationConstants.tierBalancedMidRangeLabel,
          ),
        VrDeviceCapabilityTier.accessibleEntryLevel =>
          const VrUniversalQualityBudget(
            tier: VrDeviceCapabilityTier.accessibleEntryLevel,
            renderScaleFactor: VrCoreConstants.accessibleRenderScaleFactor,
            targetFps: VrCoreConstants.accessibleTargetFps,
            maxActiveLights: VrCoreConstants.accessibleMaxActiveLights,
            maxParticleCount: VrCoreConstants.accessibleMaxParticleCount,
            enablePostProcessing: false,
            enableFullTriCameraCv: false,
            sensorFusionHz: VrCoreConstants.accessibleSensorFusionHz,
            label: VrCoreTranslationConstants.tierAccessibleEntryLevelLabel,
          ),
        VrDeviceCapabilityTier.singlePhoneStandalone =>
          const VrUniversalQualityBudget(
            tier: VrDeviceCapabilityTier.singlePhoneStandalone,
            renderScaleFactor: VrCoreConstants.standaloneRenderScaleFactor,
            targetFps: VrCoreConstants.standaloneTargetFps,
            maxActiveLights: VrCoreConstants.standaloneMaxActiveLights,
            maxParticleCount: VrCoreConstants.standaloneMaxParticleCount,
            enablePostProcessing: false,
            enableFullTriCameraCv: false,
            sensorFusionHz: VrCoreConstants.standaloneSensorFusionHz,
            label: VrCoreTranslationConstants.tierSinglePhoneStandaloneLabel,
          ),
      };

  /// Smoothly adapts [currentBudget] to the measured [averageFrameTimeMs] to
  /// prevent VR motion sickness on thermal throttling or heavy scenes.
  VrUniversalQualityBudget adaptToLiveFrameTime({
    required VrUniversalQualityBudget currentBudget,
    required double averageFrameTimeMs,
  }) {
    if (!averageFrameTimeMs.isFinite || averageFrameTimeMs <= 0) {
      return currentBudget;
    }

    final frameBudget = currentBudget.frameBudgetMs;
    final overrunThreshold = frameBudget * VrCoreConstants.frameBudgetOverrunRatio;
    final headroomThreshold =
        frameBudget * VrCoreConstants.frameBudgetHeadroomRatio;

    if (averageFrameTimeMs > overrunThreshold) {
      final nextScale = _roundScale(
        math.max(
          VrCoreConstants.minRenderScaleFactor,
          currentBudget.renderScaleFactor - VrCoreConstants.renderScaleStepDown,
        ),
      );
      if (nextScale < currentBudget.renderScaleFactor) {
        return currentBudget.copyWith(
          renderScaleFactor: nextScale,
          enablePostProcessing: false,
        );
      }
      final fallbackTier = _stepDownTier(currentBudget.tier);
      if (fallbackTier != currentBudget.tier) {
        return budgetForTier(fallbackTier);
      }
      return currentBudget.copyWith(
        renderScaleFactor: VrCoreConstants.minRenderScaleFactor,
        enablePostProcessing: false,
      );
    }

    if (averageFrameTimeMs < headroomThreshold) {
      final nominal = budgetForTier(currentBudget.tier);
      if (currentBudget.renderScaleFactor < nominal.renderScaleFactor) {
        final nextScale = _roundScale(
          math.min(
            nominal.renderScaleFactor,
            currentBudget.renderScaleFactor + VrCoreConstants.renderScaleStepUp,
          ),
        );
        return currentBudget.copyWith(
          renderScaleFactor: nextScale,
          enablePostProcessing:
              nextScale >= nominal.renderScaleFactor
              ? nominal.enablePostProcessing
              : currentBudget.enablePostProcessing,
        );
      }
    }

    return currentBudget;
  }

  VrDeviceCapabilityTier _stepDownTier(VrDeviceCapabilityTier tier) =>
      switch (tier) {
        VrDeviceCapabilityTier.ultraFlagship =>
          VrDeviceCapabilityTier.balancedMidRange,
        VrDeviceCapabilityTier.balancedMidRange =>
          VrDeviceCapabilityTier.accessibleEntryLevel,
        VrDeviceCapabilityTier.accessibleEntryLevel =>
          VrDeviceCapabilityTier.accessibleEntryLevel,
        VrDeviceCapabilityTier.singlePhoneStandalone =>
          VrDeviceCapabilityTier.accessibleEntryLevel,
      };

  double _roundScale(double value) => (value * 100.0).roundToDouble() / 100.0;
}
