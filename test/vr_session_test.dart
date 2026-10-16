import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('construction does not start a renderer', () async {
    final events = <String>[];
    final controller = VrSessionController(adapter: _adapter(events));
    expect(events, isEmpty);
    expect(controller.status.value, VrSessionStatus.idle);
    await controller.closeSession();
    controller.dispose();
    expect(events, ['close']);
  });

  test(
    'operations are serialized and repeated requests are idempotent',
    () async {
      final events = <String>[];
      final controller = VrSessionController(adapter: _adapter(events));
      await controller.pause();
      await controller.resume();
      final operations = [
        controller.start(),
        controller.start(),
        controller.pause(),
        controller.pause(),
        controller.resume(),
        controller.resume(),
      ];
      await Future.wait(operations);
      expect(events, ['start', 'pause', 'resume']);
      expect(controller.status.value, VrSessionStatus.running);
      final close = controller.closeSession();
      expect(controller.isClosed, isTrue);
      expect(identical(close, controller.closeSession()), isTrue);
      await close;
      await controller.start();
      await controller.pause();
      await controller.resume();
      expect(events, ['start', 'pause', 'resume', 'close']);
      expect(controller.status.value, VrSessionStatus.closed);
    },
  );

  test(
    'closing waits for start and discards queued lifecycle operations',
    () async {
      final ready = Completer<void>();
      final events = <String>[];
      final controller = VrSessionController(
        adapter: _adapter(
          events,
          start: () async {
            events.add('start');
            await ready.future;
            events.add('ready');
          },
        ),
      );
      final starting = controller.start();
      await Future<void>.delayed(Duration.zero);
      final pausing = controller.pause();
      final closing = controller.closeSession();
      expect(events, ['start']);
      ready.complete();
      await Future.wait([starting, pausing, closing]);
      expect(events, ['start', 'ready', 'close']);
      expect(controller.status.value, VrSessionStatus.closed);
    },
  );

  test('close before queued start prevents initialization', () async {
    final events = <String>[];
    final controller = VrSessionController(adapter: _adapter(events));
    final start = controller.start();
    await controller.closeSession();
    await start;
    expect(events, ['close']);
  });

  test('failed start remains observable and cleanup still runs', () async {
    final events = <String>[];
    final failure = StateError('initialization');
    final controller = VrSessionController(
      adapter: _adapter(events, start: () => throw failure),
    );
    await expectLater(controller.start(), throwsA(same(failure)));
    expect(controller.lastError, same(failure));
    expect(controller.lastStackTrace, isNotNull);
    expect(controller.status.value, VrSessionStatus.failed);
    await controller.resume();
    await controller.closeSession();
    expect(events, ['close']);
  });

  test('failed pause does not poison cleanup queue', () async {
    final events = <String>[];
    final failure = StateError('pause');
    final controller = VrSessionController(
      adapter: _adapter(events, pause: () => throw failure),
    );
    await controller.start();
    await expectLater(controller.pause(), throwsA(same(failure)));
    await controller.closeSession();
    expect(events, ['start', 'close']);
    expect(controller.lastError, same(failure));
  });

  test('cleanup failure closes terminally and is not retried', () async {
    var closes = 0;
    final failure = StateError('cleanup');
    final controller = VrSessionController(
      adapter: _adapter(
        [],
        close: () {
          closes++;
          throw failure;
        },
      ),
    );
    await expectLater(controller.closeSession(), throwsA(same(failure)));
    await expectLater(controller.closeSession(), throwsA(same(failure)));
    expect(controller.status.value, VrSessionStatus.closed);
    expect(controller.lastError, same(failure));
    expect(closes, 1);
  });

  test('dispose handles cleanup error and preserves it', () async {
    final failure = StateError('async cleanup');
    final controller = VrSessionController(
      adapter: _adapter(
        [],
        close: () async {
          throw failure;
        },
      ),
    );
    controller.dispose();
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(controller.isClosed, isTrue);
    expect(controller.status.value, VrSessionStatus.closed);
    expect(controller.lastError, same(failure));
  });
}

VrSessionAdapter _adapter(
  List<String> events, {
  VrSessionCallback? start,
  VrSessionCallback? pause,
  VrSessionCallback? close,
}) => VrCallbackSessionAdapter(
  rendererId: 'test',
  onStart: start ?? () => events.add('start'),
  onPause: pause ?? () => events.add('pause'),
  onResume: () => events.add('resume'),
  onClose: close ?? () => events.add('close'),
);
