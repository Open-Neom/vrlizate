import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

final class _GamepadDriver implements VrInputDriver {
  VrInputSink? sink;
  bool detached = false;

  @override
  VrInputSource get source => VrInputSource.gamepad;

  @override
  void attach(VrInputSink sink) {
    this.sink = sink;
  }

  @override
  void detach() {
    detached = true;
    sink = null;
  }
}

void main() {
  group('VrInputArbiter', () {
    late int now;
    late VrInputArbiter arbiter;
    late int delivered;

    setUp(() {
      now = 0;
      delivered = 0;
      arbiter = VrInputArbiter(
        suppressionWindow: const Duration(milliseconds: 400),
        poolCapacity: 4,
        clock: () => now,
      );
      arbiter.addListener((_) => delivered++);
    });

    tearDown(() {
      arbiter.pool.assertNoLeaks();
      arbiter.dispose();
    });

    test('suppresses gaze dwell while remote phone is active', () {
      final remote = arbiter.acquire(
        type: VrInputType.navigate,
        source: VrInputSource.remotePhone,
      );
      expect(arbiter.submit(remote), isTrue);
      arbiter.release(remote);

      now = const Duration(milliseconds: 100).inMicroseconds;
      final gazeDwell = arbiter.acquire(
        type: VrInputType.select,
        source: VrInputSource.gaze,
        targetId: 'start-button',
      );
      expect(arbiter.submit(gazeDwell), isFalse);
      arbiter.release(gazeDwell);

      expect(arbiter.isGazeSuppressed, isTrue);
      expect(delivered, 1);
    });

    test('reactivates gaze after the hysteresis period', () {
      final touch = arbiter.acquire(
        type: VrInputType.select,
        source: VrInputSource.touch,
      );
      arbiter.submit(touch);
      arbiter.release(touch);

      now = const Duration(milliseconds: 399).inMicroseconds;
      final earlyGaze = arbiter.acquire(
        type: VrInputType.select,
        source: VrInputSource.gaze,
      );
      expect(arbiter.submit(earlyGaze), isFalse);
      arbiter.release(earlyGaze);

      now = const Duration(milliseconds: 400).inMicroseconds;
      final resumedGaze = arbiter.acquire(
        type: VrInputType.select,
        source: VrInputSource.gaze,
      );
      expect(arbiter.submit(resumedGaze), isTrue);
      arbiter.release(resumedGaze);

      expect(arbiter.isGazeSuppressed, isFalse);
      expect(delivered, 2);
    });

    test('reuses pooled events without leaks', () {
      final first = arbiter.acquire(
        type: VrInputType.hover,
        source: VrInputSource.gaze,
        targetId: 'first',
      );
      arbiter.release(first);

      for (var i = 0; i < 1000; i++) {
        now = i;
        final event = arbiter.acquire(
          type: VrInputType.hover,
          source: VrInputSource.gaze,
          targetId: 'target',
        );
        expect(event, same(first));
        expect(arbiter.submit(event), isTrue);
        arbiter.release(event);
      }

      expect(arbiter.pool.inUseCount, 0);
      expect(arbiter.pool.availableCount, arbiter.pool.capacity);
      expect(arbiter.pool.peakInUse, 1);
      expect(arbiter.pool.totalAcquisitions, 1001);
    });

    test('binds community drivers to their declared source', () {
      final driver = _GamepadDriver();
      VrInputSource? deliveredSource;
      arbiter.addListener((event) => deliveredSource = event.source);

      arbiter.attachDriver(driver);
      expect(
        driver.sink!.emit(type: VrInputType.select, targetId: 'menu'),
        isTrue,
      );

      expect(deliveredSource, VrInputSource.gamepad);
      expect(arbiter.detachDriver(driver), isTrue);
      expect(driver.detached, isTrue);
    });
  });
}
