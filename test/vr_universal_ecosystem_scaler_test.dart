import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  const scaler = VrUniversalEcosystemScaler();

  group('VrUniversalEcosystemScaler hardware classification', () {
    test('classifies flagship smartphone with paired controller as ultraFlagship', () {
      final tier = scaler.classifyDevice(
        ramMegabytes: 8192,
        cpuCores: 8,
        displayRefreshHz: 120.0,
        hasPairedSecondPhone: true,
      );
      expect(tier, VrDeviceCapabilityTier.ultraFlagship);

      final budget = scaler.budgetForTier(tier);
      expect(budget.renderScaleFactor, VrCoreConstants.ultraRenderScaleFactor);
      expect(budget.targetFps, VrCoreConstants.ultraTargetFps);
      expect(budget.enablePostProcessing, isTrue);
      expect(budget.enableFullTriCameraCv, isTrue);
      expect(budget.label, VrCoreTranslationConstants.tierUltraFlagshipLabel);
    });

    test('classifies mid-range smartphone as balancedMidRange', () {
      final tier = scaler.classifyDevice(
        ramMegabytes: 4096,
        cpuCores: 8,
        displayRefreshHz: 60.0,
        hasPairedSecondPhone: true,
      );
      expect(tier, VrDeviceCapabilityTier.balancedMidRange);

      final budget = scaler.budgetForTier(tier);
      expect(
        budget.renderScaleFactor,
        VrCoreConstants.balancedRenderScaleFactor,
      );
      expect(budget.targetFps, VrCoreConstants.balancedTargetFps);
      expect(budget.enableFullTriCameraCv, isTrue);
    });

    test('classifies budget entry-level smartphone as accessibleEntryLevel', () {
      final tier = scaler.classifyDevice(
        ramMegabytes: 2048,
        cpuCores: 4,
        displayRefreshHz: 60.0,
        hasPairedSecondPhone: true,
      );
      expect(tier, VrDeviceCapabilityTier.accessibleEntryLevel);

      final budget = scaler.budgetForTier(tier);
      expect(
        budget.renderScaleFactor,
        VrCoreConstants.accessibleRenderScaleFactor,
      );
      expect(budget.enablePostProcessing, isFalse);
      expect(budget.enableFullTriCameraCv, isFalse);
      expect(
        budget.label,
        VrCoreTranslationConstants.tierAccessibleEntryLevelLabel,
      );
    });

    test('classifies single-phone visor setup as singlePhoneStandalone', () {
      final tier = scaler.classifyDevice(
        ramMegabytes: 8192,
        cpuCores: 8,
        displayRefreshHz: 120.0,
        hasPairedSecondPhone: false,
      );
      expect(tier, VrDeviceCapabilityTier.singlePhoneStandalone);

      final budget = scaler.budgetForTier(tier);
      expect(
        budget.renderScaleFactor,
        VrCoreConstants.standaloneRenderScaleFactor,
      );
      expect(budget.enableFullTriCameraCv, isFalse);
      expect(
        budget.label,
        VrCoreTranslationConstants.tierSinglePhoneStandaloneLabel,
      );
    });
  });

  group('VrUniversalEcosystemScaler live frame-time adaptation', () {
    test('steps down render scale and disables post-processing on frame overrun', () {
      final initial = scaler.budgetForTier(
        VrDeviceCapabilityTier.balancedMidRange,
      );
      final adapted = scaler.adaptToLiveFrameTime(
        currentBudget: initial,
        averageFrameTimeMs: 22.5,
      );

      expect(adapted.renderScaleFactor, lessThan(initial.renderScaleFactor));
      expect(adapted.enablePostProcessing, isFalse);
    });

    test('steps down capability tier when already at minimum render scale', () {
      final floorBudget = scaler
          .budgetForTier(VrDeviceCapabilityTier.ultraFlagship)
          .copyWith(renderScaleFactor: VrCoreConstants.minRenderScaleFactor);

      final downgraded = scaler.adaptToLiveFrameTime(
        currentBudget: floorBudget,
        averageFrameTimeMs: 25.0,
      );

      expect(downgraded.tier, VrDeviceCapabilityTier.balancedMidRange);
    });

    test('smoothly recovers render scale when frame headroom is abundant', () {
      final nominal = scaler.budgetForTier(
        VrDeviceCapabilityTier.balancedMidRange,
      );
      final throttled = nominal.copyWith(
        renderScaleFactor: 0.65,
        enablePostProcessing: false,
      );

      final recovered = scaler.adaptToLiveFrameTime(
        currentBudget: throttled,
        averageFrameTimeMs: 9.0,
      );

      expect(
        recovered.renderScaleFactor,
        greaterThan(throttled.renderScaleFactor),
      );
    });
  });
}
