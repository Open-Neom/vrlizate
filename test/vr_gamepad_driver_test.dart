import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

final class _EventSnapshot {
  final VrInputType type;
  final VrInputSource source;
  final bool active;
  final VrGamepadButton? button;
  final VrGamepadStick? stick;
  final double? value;
  final double? x;
  final double? y;

  _EventSnapshot(VrInputEvent event)
    : type = event.type,
      source = event.source,
      active = event.active,
      button = event.data?[VrGamepadDriver.buttonKey] as VrGamepadButton?,
      stick = event.data?[VrGamepadDriver.stickKey] as VrGamepadStick?,
      value = event.data?[VrGamepadDriver.valueKey] as double?,
      x = event.data?[VrGamepadDriver.xKey] as double?,
      y = event.data?[VrGamepadDriver.yKey] as double?;
}

void main() {
  group('VrGamepadDriver', () {
    late VrInputArbiter arbiter;
    late VrGamepadDriver driver;
    late List<_EventSnapshot> events;

    setUp(() {
      arbiter = VrInputArbiter(poolCapacity: 4);
      driver = VrGamepadDriver();
      events = <_EventSnapshot>[];
      arbiter.addListener((event) => events.add(_EventSnapshot(event)));
    });

    tearDown(() {
      if (driver.isAttached) arbiter.detachDriver(driver);
      arbiter.pool.assertNoLeaks();
      arbiter.dispose();
    });

    test('connects a gamepad sink with medium priority', () {
      expect(driver.isAttached, isFalse);
      expect(driver.source, VrInputSource.gamepad);
      expect(VrInputArbiter.priorityOf(driver.source), VrInputPriority.medium);

      arbiter.attachDriver(driver);

      expect(driver.isAttached, isTrue);
      expect(driver.updateButton(VrGamepadButton.a, true), isTrue);
      expect(events.single.source, VrInputSource.gamepad);
    });

    test('translates A B X and Y button edges', () {
      arbiter.attachDriver(driver);

      expect(driver.updateButton(VrGamepadButton.a, true), isTrue);
      expect(driver.updateButton(VrGamepadButton.a, false), isFalse);
      expect(driver.updateButton(VrGamepadButton.b, true), isTrue);
      expect(driver.updateButton(VrGamepadButton.x, true), isTrue);
      expect(driver.updateButton(VrGamepadButton.x, false), isTrue);
      expect(driver.updateButton(VrGamepadButton.y, true), isTrue);

      expect(events.map((event) => event.type), <VrInputType>[
        VrInputType.select,
        VrInputType.back,
        VrInputType.trigger,
        VrInputType.trigger,
        VrInputType.trigger,
      ]);
      expect(events.map((event) => event.button), <VrGamepadButton>[
        VrGamepadButton.a,
        VrGamepadButton.b,
        VrGamepadButton.x,
        VrGamepadButton.x,
        VrGamepadButton.y,
      ]);
      expect(events[2].active, isTrue);
      expect(events[3].active, isFalse);
      expect(events[3].value, 0.0);
    });

    test('translates analog triggers and sticks', () {
      arbiter.attachDriver(driver);

      expect(driver.updateTrigger(VrGamepadButton.l2, 0.75), isTrue);
      expect(driver.updateTrigger(VrGamepadButton.r2, 0.0), isTrue);
      expect(driver.updateStick(0.5, -0.25), isTrue);
      expect(driver.updateStick(0.05, 0.05), isTrue);

      expect(events[0].type, VrInputType.trigger);
      expect(events[0].button, VrGamepadButton.l2);
      expect(events[0].value, 0.75);
      expect(events[0].active, isTrue);

      expect(events[1].button, VrGamepadButton.r2);
      expect(events[1].active, isFalse);

      expect(events[2].type, VrInputType.navigate);
      expect(events[2].stick, VrGamepadStick.left);
      expect(events[2].x, 0.5);
      expect(events[2].y, -0.25);
      expect(events[2].active, isTrue);

      expect(events[3].x, 0.0);
      expect(events[3].y, 0.0);
      expect(events[3].active, isFalse);
    });

    test('detaches without leaking pooled events', () {
      arbiter.attachDriver(driver);
      for (var i = 0; i < 1000; i++) {
        driver.updateStick(i.isEven ? 0.8 : 0, i.isEven ? -0.4 : 0);
      }

      expect(arbiter.pool.inUseCount, 0);
      expect(arbiter.pool.peakInUse, 1);
      final acquisitionsBeforeDetach = arbiter.pool.totalAcquisitions;

      expect(arbiter.detachDriver(driver), isTrue);
      expect(driver.isAttached, isFalse);
      expect(driver.updateButton(VrGamepadButton.a, true), isFalse);
      expect(driver.updateTrigger(VrGamepadButton.l2, 1), isFalse);
      expect(driver.updateStick(1, 1), isFalse);

      expect(arbiter.pool.totalAcquisitions, acquisitionsBeforeDetach);
      expect(arbiter.pool.inUseCount, 0);
    });
  });
}
