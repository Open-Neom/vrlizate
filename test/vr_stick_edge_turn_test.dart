import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/core/input/vr_stick_edge_turn.dart';

class _Walker {
  _Walker({this.heading = 0, VrStickEdgeTurn? policy})
    : policy = policy ?? VrStickEdgeTurn();

  final VrStickEdgeTurn policy;
  double heading;
  VrStickEdgeTurnResult tick(
    double x,
    double y, {
    double dt = 1 / 120,
    double? intentX,
    double? intentY,
    bool? atEdge,
    bool manualLook = false,
  }) {
    final result = policy.update(
      stickX: x,
      stickY: y,
      heading: heading,
      dt: dt,
      intentX: intentX,
      intentY: intentY,
      atEdge: atEdge,
      manualLook: manualLook,
    );
    heading += result.yawDelta;
    return result;
  }

  VrStickEdgeTurnResult hold(
    double x,
    double y, {
    int frames = 1200,
    double? intentX,
    double? intentY,
  }) {
    late VrStickEdgeTurnResult result;
    for (var i = 0; i < frames; i++) {
      result = tick(x, y, intentX: intentX, intentY: intentY);
    }
    return result;
  }
}

void main() {
  test('partial stick preserves strafing and backward steps indefinitely', () {
    for (final axes in [(.7, 0.0), (-.7, 0.0), (0.0, -.7)]) {
      final walker = _Walker();
      final result = walker.hold(axes.$1, axes.$2);
      expect(result.engaged, isFalse);
      expect(walker.heading, 0);
      expect(result.movementX, axes.$1);
      expect(result.movementY, axes.$2);
    }
  });

  test('full backward edge permits initial steps before gradual turning', () {
    final walker = _Walker();
    final initial = walker.hold(0, -1, frames: 72);
    expect(walker.heading, 0);
    expect(initial.movementY, -1);
    walker.hold(0, -1, frames: 24);
    expect(walker.heading, lessThan(0));
    expect(walker.heading.abs(), lessThan(.04));
  });

  test('held six oclock completes a half turn and stops', () {
    final walker = _Walker();
    final result = walker.hold(0, -1);
    expect(walker.heading, closeTo(-math.pi, 1e-8));
    expect(result.engaged, isTrue);
    expect(result.yawDelta, closeTo(0, 1e-9));
    expect(result.movementX, closeTo(0, 1e-8));
    expect(result.movementY, closeTo(1, 1e-8));
    walker.hold(0, -1);
    expect(walker.heading, closeTo(-math.pi, 1e-8));
  });

  test('left and right edges choose their shortest quarter turns', () {
    for (final x in [-1.0, 1.0]) {
      final walker = _Walker();
      walker.hold(x, 0);
      expect(walker.heading, closeTo(-x * math.pi / 2, 1e-8));
    }
  });

  test('all octants settle at their requested heading', () {
    for (var clock = 0; clock < 8; clock++) {
      final angle = clock * math.pi / 4;
      final walker = _Walker();
      walker.hold(math.sin(angle), math.cos(angle));
      expect(math.sin(walker.heading), closeTo(-math.sin(angle), 1e-8));
      expect(math.cos(walker.heading), closeTo(math.cos(angle), 1e-8));
    }
  });

  test('movement direction remains stable through automatic turn', () {
    final walker = _Walker(heading: .7);
    for (var i = 0; i < 1200; i++) {
      final result = walker.tick(0, -1);
      final worldX =
          math.cos(walker.heading) * result.movementX -
          math.sin(walker.heading) * result.movementY;
      final worldZ =
          -math.sin(walker.heading) * result.movementX -
          math.cos(walker.heading) * result.movementY;
      expect(worldX, closeTo(math.sin(.7), 1e-8));
      expect(worldZ, closeTo(math.cos(.7), 1e-8));
    }
    expect(walker.heading, closeTo(.7 - math.pi, 1e-8));
  });

  test('raw edge intent does not bypass conditioned movement magnitude', () {
    final walker = _Walker();
    final result = walker.hold(0, -.5, intentX: 0, intentY: -1);
    expect(result.engaged, isTrue);
    expect(walker.heading, closeTo(-math.pi, 1e-8));
    expect(result.movementY, closeTo(.5, 1e-8));
  });

  test('explicit edge bit engages during gain ramp without raising speed', () {
    final walker = _Walker();
    for (var i = 0; i < 80; i++) {
      final result = walker.tick(0, -.5, atEdge: true);
      expect(
        math.sqrt(
          result.movementX * result.movementX +
              result.movementY * result.movementY,
        ),
        closeTo(.5, 1e-8),
      );
    }
    expect(walker.policy.engaged, isTrue);
    expect(walker.heading, lessThan(0));
  });

  test('explicit false edge prevents and releases even full shaped input', () {
    final walker = _Walker();
    for (var i = 0; i < 1200; i++) {
      expect(walker.tick(0, -1, atEdge: false).engaged, isFalse);
    }
    expect(walker.heading, 0);
    walker.hold(0, -1, frames: 120);
    expect(walker.policy.engaged, isTrue);
    final released = walker.tick(0, -1, atEdge: false);
    expect(released.engaged, isFalse);
    expect(released.yawDelta, 0);
    expect(released.movementY, -1);
    walker.hold(0, -1, frames: 60);
    expect(walker.policy.engaged, isFalse);
  });

  test('stick angle changes adjust the target instead of relatching it', () {
    final walker = _Walker();
    walker.hold(1, 0);
    expect(walker.heading, closeTo(-math.pi / 2, 1e-8));
    walker.hold(0, -1);
    expect(walker.heading, closeTo(-math.pi, 1e-8));
    walker.hold(0, 1);
    expect(math.sin(walker.heading), closeTo(0, 1e-8));
    expect(math.cos(walker.heading), closeTo(1, 1e-8));
  });

  test('approach from either side decides the exact backward tie', () {
    for (final side in [-1.0, 1.0]) {
      final walker = _Walker();
      walker.tick(side * .5, 0);
      walker.hold(0, -1);
      expect(walker.heading, closeTo(-side * math.pi, 1e-8));
    }
  });

  test('a left arc during dwell overrides the default clockwise tie', () {
    final walker = _Walker();
    for (var step = 0; step <= 24; step++) {
      final angle = step * math.pi / 24;
      walker.tick(-math.sin(angle), math.cos(angle));
    }
    walker.hold(0, -1);
    expect(walker.heading, closeTo(math.pi, 1e-8));
  });

  test('small jitter across six oclock never reverses the initial turn', () {
    final walker = _Walker();
    for (var i = 0; i < 180; i++) {
      final result = walker.tick(i.isEven ? .0005 : -.0005, -1);
      expect(result.yawDelta, lessThanOrEqualTo(0));
    }
    walker.hold(0, -1);
    expect(walker.heading, closeTo(-math.pi, 1e-8));
  });

  test('dwell resets below the edge, then has hysteresis after engagement', () {
    final walker = _Walker();
    walker.hold(0, -1, frames: 60);
    walker.tick(0, -.9);
    walker.hold(0, -1, frames: 60);
    expect(walker.heading, 0);
    walker.hold(0, -1, frames: 30);
    expect(walker.policy.engaged, isTrue);
    expect(walker.tick(0, -.9).engaged, isTrue);
    expect(walker.tick(0, -.8).engaged, isFalse);
  });

  test('manual look interrupts until left stick is neutral', () {
    final walker = _Walker();
    walker.hold(0, -1, frames: 120);
    walker.tick(0, -1, manualLook: true);
    final stoppedHeading = walker.heading;
    final interrupted = walker.hold(0, -1);
    expect(interrupted.engaged, isFalse);
    expect(walker.heading, stoppedHeading);
    walker.tick(0, 0);
    walker.hold(0, -1, frames: 120);
    expect(walker.heading, lessThan(stoppedHeading));
  });

  test('release, reset and zero stale input cannot retain a turn', () {
    final walker = _Walker();
    walker.hold(0, -1, frames: 120);
    final stopped = walker.tick(0, 0, intentX: 0, intentY: -1);
    expect(stopped.engaged, isFalse);
    expect(stopped.yawDelta, 0);
    walker.hold(0, -1, frames: 60);
    expect(walker.policy.engaged, isFalse);
    walker.policy.reset();
    walker.hold(0, -1, frames: 60);
    expect(walker.policy.engaged, isFalse);
  });

  test(
    'long frames are capped rather than completing dwell or teleporting',
    () {
      final walker = _Walker();
      expect(walker.tick(0, -1, dt: 10).engaged, isFalse);
      walker.hold(0, -1, frames: 120);
      final result = walker.tick(0, -1, dt: 10);
      expect(
        result.yawDelta.abs(),
        lessThanOrEqualTo(walker.policy.maxYawSpeed * .05),
      );
    },
  );

  test('30, 60, 90 and 120 Hz produce bounded turns to the same target', () {
    for (final hz in [30, 60, 90, 120]) {
      final walker = _Walker();
      for (var i = 0; i < hz * 10; i++) {
        final result = walker.tick(0, -1, dt: 1 / hz);
        expect(
          result.yawDelta.abs(),
          lessThanOrEqualTo(walker.policy.maxYawSpeed / hz + 1e-10),
        );
      }
      expect(walker.heading, closeTo(-math.pi, 1e-8));
    }
  });

  test('invalid input safely clears state and disabled policy passes axes', () {
    final policy = VrStickEdgeTurn();
    for (final args in [
      (double.nan, 0.0, 0.0, .1),
      (0.0, double.infinity, 0.0, .1),
      (0.0, -1.0, double.nan, .1),
      (0.0, -1.0, 0.0, -1.0),
    ]) {
      final result = policy.update(
        stickX: args.$1,
        stickY: args.$2,
        heading: args.$3,
        dt: args.$4,
      );
      expect(result.yawDelta, 0);
      expect(result.movementX, 0);
      expect(result.movementY, 0);
      expect(policy.engaged, isFalse);
    }
    final disabled = policy.update(
      stickX: 1,
      stickY: 1,
      heading: 0,
      dt: 1,
      enabled: false,
    );
    expect(disabled.yawDelta, 0);
    expect(disabled.movementX, closeTo(math.sqrt(.5), 1e-8));
    expect(disabled.movementY, closeTo(math.sqrt(.5), 1e-8));
  });

  test('invalid configuration fails early', () {
    expect(() => VrStickEdgeTurn(edgeThreshold: .8), throwsArgumentError);
    expect(() => VrStickEdgeTurn(releaseThreshold: .1), throwsArgumentError);
    expect(() => VrStickEdgeTurn(holdSeconds: 0), throwsArgumentError);
    expect(() => VrStickEdgeTurn(maxYawSpeed: double.nan), throwsArgumentError);
  });
}
