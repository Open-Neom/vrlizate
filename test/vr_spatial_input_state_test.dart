import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  test('a suppressed gamepad release still stops its own held input', () {
    final arbiter = VrInputArbiter();
    final state = VrSpatialInputState();
    arbiter.addListener(state.handleEvent);
    arbiter.emit(
      type: VrInputType.navigate,
      source: VrInputSource.gamepad,
      data: {'x': 1},
    );
    arbiter.emit(type: VrInputType.select, source: VrInputSource.remotePhone);
    arbiter.emit(
      type: VrInputType.navigate,
      source: VrInputSource.gamepad,
      active: false,
    );
    state.update(1);
    expect(state.moveX, 0);
    arbiter.emit(
      type: VrInputType.navigate,
      source: VrInputSource.remotePhone,
      data: {'x': 0.7},
    );
    arbiter.emit(
      type: VrInputType.navigate,
      source: VrInputSource.gamepad,
      active: false,
    );
    expect(state.moveX, 0.7); // A different source cannot release the owner.
    arbiter.dispose();
  });

  test('explicit miss clears a prior dwell target without grace', () {
    final pointer = GazePointer(cameraRig: CameraRig(), enableHaptics: false);
    var selections = 0;
    pointer.onTap = (_) => selections++;
    pointer.update(0, 'old');
    pointer.update(0, null, dwellEnabled: false, allowGrace: false);
    pointer.triggerTap(null);
    expect(pointer.gazeTargetId, isNull);
    expect(selections, 0);
  });

  final forward = Vector3(0, 0, -1);
  final right = Vector3(1, 0, 0);
  final up = Vector3(0, 1, 0);

  VrInputEvent navigation(Map<String, dynamic> data, {bool active = true}) =>
      VrInputEvent(
        type: VrInputType.navigate,
        source: VrInputSource.remotePhone,
        data: data,
        active: active,
      );

  test(
    '60 and 120 packet rates produce identical movement over one second',
    () {
      Vector3 simulate(int packetRate) {
        final arbiter = VrInputArbiter();
        final engine = VREngine()..bindInput(arbiter);
        for (var i = 0; i < 120; i++) {
          if (i % (120 ~/ packetRate) == 0) {
            arbiter.emit(
              type: VrInputType.navigate,
              source: VrInputSource.remotePhone,
              data: {'y': 1},
            );
          }
          engine.updateInput(1 / 120);
        }
        final result = engine.cameraRig.position.clone();
        engine.dispose();
        arbiter.pool.assertNoLeaks();
        arbiter.dispose();
        return result;
      }

      final at60 = simulate(60);
      final at120 = simulate(120);
      expect((at60 - at120).length, lessThan(1e-10));
      expect(at60.z, closeTo(-3, 1e-5));
    },
  );

  test('horizontal movement preserves height and clamps diagonal speed', () {
    final state = VrSpatialInputState()
      ..handleEvent(navigation({'x': 1, 'y': 1}));
    final delta = Vector3.zero();
    state.writeMovement(
      delta,
      forward: Vector3(0, -0.9, -0.1),
      screenRight: right,
      dt: 1,
    );
    expect(delta.y, 0);
    expect(delta.length, closeTo(3, 1e-6));
    expect(delta.x, greaterThan(0));
    expect(delta.z, lessThan(0));
  });

  test('remote silence and release stop movement and looking', () {
    final state = VrSpatialInputState()
      ..handleEvent(navigation({'x': 1, 'lookY': 1}));
    state.update(0.49);
    expect(state.moveX, 1);
    state.update(0.02);
    expect(state.moveX, 0);
    expect(state.lookY, 0);
    state.handleEvent(navigation({'y': 1, 'lookX': 1}));
    state.handleEvent(navigation({}, active: false));
    expect(state.moveY, 0);
    expect(state.lookX, 0);
  });

  test('gamepad sticks are independent and hold until their release edge', () {
    final arbiter = VrInputArbiter();
    final driver = VrGamepadDriver();
    final state = VrSpatialInputState();
    arbiter.addListener(state.handleEvent);
    arbiter.attachDriver(driver);
    driver.updateStick(0, 1);
    driver.updateStick(1, 0, stick: VrGamepadStick.right);
    state.update(2);
    expect(state.moveY, 1);
    expect(state.lookX, 1);
    driver.updateStick(0, 0, stick: VrGamepadStick.right);
    expect(state.moveY, 1);
    expect(state.lookX, 0);
    arbiter.dispose();
  });

  test(
    'pointer copies borrowed orientation and falls back on release/timeout',
    () {
      final arbiter = VrInputArbiter(poolCapacity: 1);
      final state = VrSpatialInputState();
      arbiter.addListener(state.handleEvent);
      final q = Quaternion.axisAngle(up, math.pi / 2);
      arbiter.emit(
        type: VrInputType.pointerMove,
        source: VrInputSource.remotePhone,
        data: {'orientation': q},
      );
      q.setValues(0, 0, 0, 1);
      final ray = Ray();
      void write() => state.writeRay(
        ray,
        origin: Vector3.zero(),
        forward: forward,
        screenRight: right,
        up: up,
      );
      write();
      expect(ray.direction.x, closeTo(-1, 1e-10));
      expect(ray.direction.z, closeTo(0, 1e-10));
      state.update(0.51);
      write();
      expect(ray.direction.z, -1);
      expect(state.pointerActive, isFalse);
      arbiter.pool.assertNoLeaks();
      arbiter.dispose();
    },
  );

  test(
    'pad ray uses renderer screen basis and zero-centered pad remains active',
    () {
      final state = VrSpatialInputState();
      final ray = Ray();
      void point(double x, double y) {
        state.handleEvent(
          VrInputEvent(
            type: VrInputType.pointerMove,
            source: VrInputSource.remotePhone,
            data: {'relativeToHead': true, 'laserX': x, 'laserY': y},
          ),
        );
        state.writeRay(
          ray,
          origin: Vector3(0, 1.6, 0),
          forward: forward,
          screenRight: -right,
          up: up,
        );
      }

      point(0, 0);
      expect(state.pointerActive, isTrue);
      expect(ray.direction.z, -1);
      point(1, 0);
      expect(ray.direction.x, closeTo(-1, 1e-10));
      point(0, 1);
      expect(ray.direction.y, greaterThan(0));
    },
  );

  test(
    'invalid axes and quaternions cannot contaminate the world transform',
    () {
      final state = VrSpatialInputState()
        ..handleEvent(
          navigation({'x': double.nan, 'y': double.infinity, 'lookX': '1'}),
        );
      expect(state.moveX, 0);
      expect(state.moveY, 0);
      expect(state.lookX, 0);
      state.handleEvent(
        VrInputEvent(
          type: VrInputType.pointerMove,
          source: VrInputSource.remotePhone,
          data: {'orientation': Quaternion(0, 0, 0, 0)},
        ),
      );
      expect(state.pointerActive, isFalse);
    },
  );

  test('consumed system actions run first and pooled handled state resets', () {
    final arbiter = VrInputArbiter(poolCapacity: 1);
    var actions = 0;
    arbiter.addListener((event) {
      if (!event.handled) actions++;
    });
    void system(VrInputEvent event) => event.consume();
    arbiter.addListener(system, first: true);
    arbiter.emit(type: VrInputType.select, source: VrInputSource.touch);
    expect(actions, 0);
    arbiter.removeListener(system);
    arbiter.emit(type: VrInputType.select, source: VrInputSource.touch);
    expect(actions, 1);
    arbiter.pool.assertNoLeaks();
    arbiter.dispose();
  });

  test('held control extends suppression without repeating its action', () {
    var now = 0;
    var actions = 0;
    final arbiter = VrInputArbiter(clock: () => now);
    arbiter.addListener((event) => actions++);
    arbiter.emit(type: VrInputType.select, source: VrInputSource.remotePhone);
    for (var i = 0; i < 10; i++) {
      now += 100000;
      arbiter.markActive(VrInputSource.remotePhone);
    }
    expect(actions, 1);
    expect(arbiter.isGazeSuppressed, isTrue);
    now += 400000;
    expect(arbiter.isGazeSuppressed, isFalse);
    arbiter.dispose();
  });

  test(
    'engine recenter preserves position and releases its arbiter listener',
    () {
      final arbiter = VrInputArbiter();
      final engine = VREngine()..bindInput(arbiter);
      engine.cameraRig.position = Vector3(2, 1.6, 3);
      engine.cameraRig.rotate(0.7, 0);
      arbiter.emit(
        type: VrInputType.recenter,
        source: VrInputSource.remotePhone,
      );
      expect(engine.cameraRig.yaw, 0);
      expect(engine.cameraRig.position.y, closeTo(1.6, 1e-6));
      engine.dispose();
      arbiter.emit(
        type: VrInputType.recenter,
        source: VrInputSource.remotePhone,
      );
      arbiter.pool.assertNoLeaks();
      arbiter.dispose();
    },
  );
}
