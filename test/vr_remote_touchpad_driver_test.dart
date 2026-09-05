import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('VrRemoteTouchpadDriver', () {
    late VrInputArbiter arbiter;
    late VrRemoteTouchpadDriver driver;
    late List<_CapturedInput> inputs;

    setUp(() {
      arbiter = VrInputArbiter(poolCapacity: 2);
      driver = VrRemoteTouchpadDriver(deadZone: 0.1);
      inputs = <_CapturedInput>[];
      arbiter.addListener((event) {
        inputs.add(
          _CapturedInput(
            type: event.type,
            active: event.active,
            x: event.data?[VrRemoteTouchpadDriver.axisXKey] as double?,
            y: event.data?[VrRemoteTouchpadDriver.axisYKey] as double?,
          ),
        );
      });
      arbiter.attachDriver(driver);
    });

    tearDown(() {
      if (driver.isAttached) arbiter.detachDriver(driver);
      arbiter.pool.assertNoLeaks();
      arbiter.dispose();
    });

    test('maps normalized touch to maximum-priority navigation', () {
      expect(driver.updateTouch(1, 0.5), isTrue);

      expect(inputs.single.type, VrInputType.navigate);
      expect(inputs.single.active, isTrue);
      expect(inputs.single.x, closeTo(1, 1e-8));
      expect(inputs.single.y, closeTo(0, 1e-8));
      expect(arbiter.isGazeSuppressed, isTrue);
      expect(arbiter.pool.totalAcquisitions, 1);
      expect(arbiter.pool.inUseCount, 0);
    });

    test('applies a radial dead zone and emits one release', () {
      driver.updateTouch(0.52, 0.48);
      expect(inputs.single.x, 0);
      expect(inputs.single.y, 0);

      expect(driver.updateTouch(null, null), isTrue);
      expect(inputs.last.active, isFalse);
      expect(inputs.last.x, 0);
      expect(inputs.last.y, 0);
      expect(driver.updateTouch(null, null), isFalse);
      expect(inputs, hasLength(2));
    });

    test('detach does not acquire or retain pooled events', () {
      driver.updateTouch(0.8, 0.2);
      final acquisitions = arbiter.pool.totalAcquisitions;

      expect(arbiter.detachDriver(driver), isTrue);
      expect(arbiter.pool.inUseCount, 0);
      expect(arbiter.pool.totalAcquisitions, acquisitions);
      expect(driver.updateTouch(0.2, 0.8), isFalse);
      expect(arbiter.pool.totalAcquisitions, acquisitions);
    });
  });
}

final class _CapturedInput {
  final VrInputType type;
  final bool active;
  final double? x;
  final double? y;

  const _CapturedInput({
    required this.type,
    required this.active,
    required this.x,
    required this.y,
  });
}
