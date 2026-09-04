import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

final class _LaserEventSnapshot {
  final VrInputType type;
  final VrInputSource source;
  final bool active;
  final Quaternion? orientation;
  final Vector3? forward;
  final bool? pressed;

  _LaserEventSnapshot(VrInputEvent event)
    : type = event.type,
      source = event.source,
      active = event.active,
      orientation = switch (event.data?[VrLaserPointerDriver.orientationKey]) {
        final Quaternion value => value.clone(),
        _ => null,
      },
      forward = switch (event.data?[VrLaserPointerDriver.forwardKey]) {
        final Vector3 value => value.clone(),
        _ => null,
      },
      pressed = event.data?[VrLaserPointerDriver.pressedKey] as bool?;
}

void main() {
  group('VrLaserPointerDriver', () {
    late VrInputArbiter arbiter;
    late VrLaserPointerDriver driver;
    late List<_LaserEventSnapshot> events;

    setUp(() {
      arbiter = VrInputArbiter(poolCapacity: 4);
      driver = VrLaserPointerDriver();
      events = <_LaserEventSnapshot>[];
      arbiter.addListener((event) => events.add(_LaserEventSnapshot(event)));
      arbiter.attachDriver(driver);
    });

    tearDown(() {
      if (driver.isAttached) arbiter.detachDriver(driver);
      arbiter.pool.assertNoLeaks();
      arbiter.dispose();
    });

    test('computes identity and 90 degree Y forward vectors', () {
      driver.updateOrientation(Quaternion.identity());
      expect(driver.forward.x, closeTo(0, 1e-9));
      expect(driver.forward.y, closeTo(0, 1e-9));
      expect(driver.forward.z, closeTo(-1, 1e-9));

      driver.updateOrientation(
        Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2),
      );
      expect(driver.forward.x, closeTo(-1, 1e-9));
      expect(driver.forward.y, closeTo(0, 1e-9));
      expect(driver.forward.z, closeTo(0, 1e-9));
    });

    test('emits pointerMove and trigger states through the sink', () {
      expect(driver.updateOrientation(Quaternion.identity()), isTrue);
      expect(driver.setTrigger(true), isTrue);
      expect(driver.setTrigger(false), isTrue);

      expect(events, hasLength(3));
      expect(events[0].type, VrInputType.pointerMove);
      expect(events[0].source, VrInputSource.remotePhone);
      expect(events[0].orientation, isNotNull);
      expect(events[0].forward, Vector3(0, 0, -1));

      expect(events[1].type, VrInputType.trigger);
      expect(events[1].pressed, isTrue);
      expect(events[1].active, isTrue);
      expect(events[2].pressed, isFalse);
      expect(events[2].active, isFalse);
    });

    test('recenters current yaw to the frontal direction', () {
      final yaw90 = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2);
      driver.updateOrientation(yaw90);
      expect(driver.forward.x, closeTo(-1, 1e-9));

      driver.recenter();
      expect(driver.yawOffsetRadians, closeTo(-math.pi / 2, 1e-9));
      expect(driver.forward.x, closeTo(0, 1e-9));
      expect(driver.forward.z, closeTo(-1, 1e-9));

      events.clear();
      expect(driver.updateOrientation(yaw90), isTrue);
      expect(events.single.forward!.x, closeTo(0, 1e-9));
      expect(events.single.forward!.z, closeTo(-1, 1e-9));
    });

    test('uses a medium priority override for remotePhone', () {
      expect(driver.source, VrInputSource.remotePhone);
      expect(driver.priority, VrInputPriority.medium);
      expect(
        VrInputArbiter.priorityOf(VrInputSource.remotePhone),
        VrInputPriority.maximum,
      );

      arbiter.emit(type: VrInputType.select, source: VrInputSource.touch);
      expect(driver.setTrigger(true), isFalse);
    });

    test('detaches safely without leaking pooled events', () {
      final orientation = Quaternion.identity();
      for (var i = 0; i < 1000; i++) {
        driver.updateOrientation(orientation);
        driver.setTrigger(i.isEven);
      }

      expect(arbiter.pool.inUseCount, 0);
      expect(arbiter.pool.peakInUse, 1);
      final acquisitionsBeforeDetach = arbiter.pool.totalAcquisitions;

      expect(arbiter.detachDriver(driver), isTrue);
      expect(driver.isAttached, isFalse);
      expect(driver.updateOrientation(orientation), isFalse);
      expect(driver.setTrigger(true), isFalse);
      driver.recenter();

      expect(arbiter.pool.totalAcquisitions, acquisitionsBeforeDetach);
      expect(arbiter.pool.inUseCount, 0);
    });
  });
}
