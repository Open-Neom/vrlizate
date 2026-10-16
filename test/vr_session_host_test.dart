import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  testWidgets('host starts, injects a scope and closes once on removal', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = <String>[];
    final adapter = _adapter(events);
    VrSessionController? session;
    await tester.pumpWidget(
      MaterialApp(
        home: VrSessionHost(
          adapter: adapter,
          builder: (context, controller, active) {
            session = controller;
            expect(VrSessionHost.of(context), same(controller));
            return Text('$active');
          },
        ),
      ),
    );
    await tester.pump();
    expect(events, ['start']);
    expect(find.text('true'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(events, ['start', 'close']);
    expect(session!.isClosed, isTrue);
    expect(session!.status.value, VrSessionStatus.closed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background launch stays idle until resumed', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    final events = <String>[];
    final adapter = _adapter(events);
    await tester.pumpWidget(
      MaterialApp(
        home: VrSessionHost(
          adapter: adapter,
          builder: (_, __, active) => Text('$active'),
        ),
      ),
    );
    await tester.pump();
    expect(events, isEmpty);
    expect(find.text('false'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(events, ['start']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(events, ['start', 'pause']);
    expect(find.text('false'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(events, ['start', 'pause']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(events, ['start', 'pause', 'resume']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('visible inactive desktop window remains active', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: VrSessionHost(
          adapter: _adapter(events),
          builder: (_, __, active) => Text('$active'),
        ),
      ),
    );
    await tester.pump();
    expect(events, ['start']);
    expect(find.text('true'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(events, ['start', 'pause']);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('covering route pauses and returning resumes', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = <String>[];
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: VrSessionHost(
          adapter: _adapter(events),
          builder: (_, __, active) => Text('session $active'),
        ),
      ),
    );
    await tester.pump();
    navigatorKey.currentState!.push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) => const Text('cover'),
      ),
    );
    await tester.pumpAndSettle();
    expect(events, ['start', 'pause']);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(events, ['start', 'pause', 'resume']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ancestor ticker mode prevents start and controls resumption', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = <String>[];
    final adapter = _adapter(events);
    Widget root(bool enabled) => MaterialApp(
      home: TickerMode(
        enabled: enabled,
        child: VrSessionHost(
          adapter: adapter,
          builder: (context, _, active) =>
              Text('$active/${TickerMode.valuesOf(context).enabled}'),
        ),
      ),
    );
    await tester.pumpWidget(root(false));
    await tester.pump();
    expect(events, isEmpty);
    expect(find.text('false/false'), findsOneWidget);
    await tester.pumpWidget(root(true));
    await tester.pump();
    expect(events, ['start']);
    await tester.pumpWidget(root(false));
    await tester.pump();
    expect(events, ['start', 'pause']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing during startup waits before cleanup with no restart', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = <String>[];
    final ready = Completer<void>();
    final adapter = _adapter(
      events,
      start: () async {
        events.add('start');
        await ready.future;
        events.add('ready');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VrSessionHost(
          adapter: adapter,
          builder: (_, __, ___) => const SizedBox(),
        ),
      ),
    );
    expect(events, ['start']);
    await tester.pumpWidget(const SizedBox());
    expect(events, ['start']);
    ready.complete();
    await tester.pump();
    expect(events, ['start', 'ready', 'close']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure is forwarded once and cleanup remains possible', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = <String>[];
    final errors = <Object>[];
    final error = StateError('renderer failed');
    await tester.pumpWidget(
      MaterialApp(
        home: VrSessionHost(
          adapter: _adapter(events, start: () => throw error),
          onError: (error, _) => errors.add(error),
          builder: (context, _, active) =>
              Text('$active/${TickerMode.valuesOf(context).enabled}'),
        ),
      ),
    );
    await tester.pump();
    expect(errors, [same(error)]);
    expect(find.text('false/false'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('false/false'), findsOneWidget);
    expect(errors, [same(error)]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(events, ['close']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external close disables frames while host remains mounted', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = <String>[];
    late VrSessionController controller;
    await tester.pumpWidget(
      MaterialApp(
        home: VrSessionHost(
          adapter: _adapter(events),
          builder: (context, session, active) {
            controller = session;
            return Text('$active/${TickerMode.valuesOf(context).enabled}');
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('true/true'), findsOneWidget);
    await controller.closeSession();
    await tester.pump();
    expect(find.text('false/false'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('false/false'), findsOneWidget);
    expect(events, ['start', 'close']);
    await tester.pumpWidget(const SizedBox());
    expect(events, ['start', 'close']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during pending startup disables frames before cleanup', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = <String>[];
    final ready = Completer<void>();
    late VrSessionController controller;
    await tester.pumpWidget(
      MaterialApp(
        home: VrSessionHost(
          adapter: _adapter(
            events,
            start: () async {
              events.add('start');
              await ready.future;
              events.add('ready');
            },
          ),
          builder: (context, session, active) {
            controller = session;
            return Text('$active/${TickerMode.valuesOf(context).enabled}');
          },
        ),
      ),
    );
    expect(controller.status.value, VrSessionStatus.starting);
    final closing = controller.closeSession();
    expect(controller.status.value, VrSessionStatus.closing);
    await tester.pump();
    expect(find.text('false/false'), findsOneWidget);
    expect(events, ['start']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('false/false'), findsOneWidget);
    expect(events, ['start']);
    ready.complete();
    await closing;
    await tester.pump();
    expect(find.text('false/false'), findsOneWidget);
    expect(events, ['start', 'ready', 'close']);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested hosts keep independent controllers', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final parentEvents = <String>[];
    final childEvents = <String>[];
    final parentAdapter = _adapter(parentEvents);
    final childAdapter = _adapter(childEvents);
    VrSessionController? parent;
    VrSessionController? child;
    Widget root(bool includeChild) => MaterialApp(
      home: VrSessionHost(
        adapter: parentAdapter,
        builder: (_, controller, __) {
          parent = controller;
          return includeChild
              ? VrSessionHost(
                  adapter: childAdapter,
                  builder: (_, controller, __) {
                    child = controller;
                    return const SizedBox();
                  },
                )
              : const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(root(true));
    await tester.pump();
    expect(parent, isNot(same(child)));
    await tester.pumpWidget(root(false));
    await tester.pump();
    expect(child!.isClosed, isTrue);
    expect(parent!.isClosed, isFalse);
    expect(parentEvents, ['start']);
    await tester.pumpWidget(const SizedBox());
  });
}

VrSessionAdapter _adapter(List<String> events, {VrSessionCallback? start}) =>
    VrCallbackSessionAdapter(
      rendererId: 'test',
      onStart: start ?? () => events.add('start'),
      onPause: () => events.add('pause'),
      onResume: () => events.add('resume'),
      onClose: () => events.add('close'),
    );
