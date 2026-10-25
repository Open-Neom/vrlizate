import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vrlizate/vrlizate.dart';

// These are channel I/O tests, not widget tests. A real event loop is needed
// for channel cancellation acknowledgements; no UI or rendering is involved.
Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const availability = MethodChannel('test/head_motion');
  const events = EventChannel('test/head_motion/gyroscope');
  const timestamp = 1792886400000000;

  test('shares native capture and preserves acquisition timestamps', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(availability, (_) async => true);
    late MockStreamHandlerEventSink sink;
    Object? arguments;
    var listens = 0, cancels = 0;
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (args, value) {
          arguments = args;
          sink = value;
          listens++;
        },
        onCancel: (_) {
          cancels++;
        },
      ),
    );
    final source = VrCoreMotionGyroscope(
      availabilityChannel: availability,
      eventChannel: events,
    );
    final a = <GyroscopeEvent>[], b = <GyroscopeEvent>[];
    final first = source.stream.listen(a.add);
    final second = source.stream.listen(b.add);
    await _flush();
    expect(listens, 1);
    expect(arguments, {'samplingPeriodUs': 10000});
    sink.success([.007, -.3, .1, timestamp]);
    sink.success([.009, -.2, .2, timestamp + 50000]);
    await _flush();
    expect(a.length, 2);
    expect(b.length, 2);
    expect(a.first.x, .007); // A slow intentional turn is not filtered out.
    expect(a.first.timestamp.microsecondsSinceEpoch, timestamp);
    expect(
      a.last.timestamp.difference(a.first.timestamp).inMicroseconds,
      50000,
    );
    await first.cancel();
    await _flush();
    expect(cancels, 0);
    await second.cancel();
    await source.dispose();
    await _flush();
    expect(cancels, 1);
  });

  test('drops malformed, corrupt and out-of-order native samples', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(availability, (_) async => true);
    late MockStreamHandlerEventSink sink;
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, value) {
          sink = value;
        },
      ),
    );
    var fallbacks = 0;
    final source = VrCoreMotionGyroscope(
      availabilityChannel: availability,
      eventChannel: events,
      fallback: () {
        fallbacks++;
        return const Stream<GyroscopeEvent>.empty();
      },
    );
    final values = <GyroscopeEvent>[];
    final subscription = source.stream.listen(values.add);
    await _flush();
    for (final value in [
      null,
      {},
      [],
      [0, 0, 0],
      [0, 0, 0, 'bad'],
      [double.nan, 0, 0, timestamp],
      [0, 0, double.infinity, timestamp],
      [101, 0, 0, timestamp],
      [0, 0, 0, -1],
      [0, 0, 0, timestamp + .5],
      [.1, .2, .3, timestamp],
      [.9, .9, .9, timestamp],
      [.9, .9, .9, timestamp - 100],
      [.4, .5, .6, timestamp + 10000],
    ]) {
      sink.success(value);
    }
    await _flush();
    expect(values.map((event) => event.x), [.1, .4]);
    expect(fallbacks, 0);
    await subscription.cancel();
    await source.dispose();
  });

  test(
    'only an absent host backend falls back once to sensors source',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(availability, null);
      var fallbacks = 0, cancels = 0;
      final fallback = StreamController<GyroscopeEvent>.broadcast(
        onCancel: () => cancels++,
      );
      final source = VrCoreMotionGyroscope(
        availabilityChannel: availability,
        eventChannel: events,
        fallback: () {
          fallbacks++;
          return fallback.stream;
        },
      );
      final values = <GyroscopeEvent>[];
      final subscription = source.stream.listen(values.add);
      await _flush();
      expect(fallbacks, 1);
      fallback.add(
        GyroscopeEvent(
          .01,
          0,
          0,
          DateTime.fromMicrosecondsSinceEpoch(timestamp),
        ),
      );
      await _flush();
      expect(values.single.x, .01);
      await subscription.cancel();
      await source.dispose();
      await fallback.close();
      expect(cancels, 1);
    },
  );

  for (final availabilityValue in [false, 'malformed', 'error']) {
    test(
      'registered backend $availabilityValue does not revert to raw gyro',
      () async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(availability, (_) async {
          if (availabilityValue == 'error') {
            throw PlatformException(code: 'motion-failed');
          }
          return availabilityValue;
        });
        var fallbacks = 0;
        final source = VrCoreMotionGyroscope(
          availabilityChannel: availability,
          eventChannel: events,
          fallback: () {
            fallbacks++;
            return const Stream<GyroscopeEvent>.empty();
          },
        );
        final errors = <Object>[];
        final subscription = source.stream.listen(
          (_) => fail('Unexpected sample'),
          onError: errors.add,
        );
        await _flush();
        expect(errors, hasLength(1));
        expect(fallbacks, 0);
        await subscription.cancel();
        await source.dispose();
      },
    );
  }

  test(
    'cancelling a pending probe stops its timeout and ignores late reply',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final reply = Completer<Object?>();
      messenger.setMockMethodCallHandler(availability, (_) => reply.future);
      var listens = 0, fallbacks = 0;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, _) {
            listens++;
          },
        ),
      );
      final source = VrCoreMotionGyroscope(
        availabilityChannel: availability,
        eventChannel: events,
        fallback: () {
          fallbacks++;
          return const Stream<GyroscopeEvent>.empty();
        },
      );
      final subscription = source.stream.listen((_) => fail('Late sample'));
      await _flush();
      await subscription.cancel();
      await source.dispose();
      reply.complete(true);
      await _flush();
      expect(listens, 0);
      expect(fallbacks, 0);
    },
  );

  test(
    'native failure does not retry and a deliberate re-listen is fresh',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(availability, (_) async => true);
      late MockStreamHandlerEventSink sink;
      var listens = 0, cancels = 0, fallbacks = 0;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, value) {
            sink = value;
            listens++;
          },
          onCancel: (_) {
            cancels++;
          },
        ),
      );
      final source = VrCoreMotionGyroscope(
        availabilityChannel: availability,
        eventChannel: events,
        fallback: () {
          fallbacks++;
          return const Stream<GyroscopeEvent>.empty();
        },
      );
      final values = <GyroscopeEvent>[], errors = <Object>[];
      var subscription = source.stream.listen(values.add, onError: errors.add);
      await _flush();
      sink.success([.01, 0, 0, timestamp]);
      sink.error(code: 'motion-failed');
      await _flush();
      expect(errors.single, isA<PlatformException>());
      expect(listens, 1);
      expect(fallbacks, 0);
      await subscription.cancel();
      subscription = source.stream.listen(values.add, onError: errors.add);
      await _flush();
      sink.success([
        .02,
        0,
        0,
        timestamp,
      ]); // Same time is valid in a new session.
      await _flush();
      expect(listens, 2);
      expect(values.map((event) => event.x), [.01, .02]);
      await subscription.cancel();
      await source.dispose();
      await _flush();
      expect(cancels, 2);
    },
  );
}
