import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('VrCurves & VrSeededRandom', () {
    test('seg, smoothstep, cubic easings, backOut, spring, and envelope', () {
      expect(VrCurves.seg(2.0, 1.0, 3.0), closeTo(0.5, 1e-6));
      expect(VrCurves.seg(0.0, 1.0, 3.0), 0.0);
      expect(VrCurves.seg(5.0, 1.0, 3.0), 1.0);

      expect(VrCurves.smoothstep(0.0), 0.0);
      expect(VrCurves.smoothstep(0.5), 0.5);
      expect(VrCurves.smoothstep(1.0), 1.0);

      expect(VrCurves.easeInOutCubic(0.5), closeTo(0.5, 1e-6));
      expect(VrCurves.backOut(0.0), closeTo(0.0, 1e-6));
      expect(VrCurves.backOut(1.0), closeTo(1.0, 1e-6));
      expect(VrCurves.backOut(0.6), greaterThan(1.0)); // subtle overshoot

      expect(VrCurves.spring(0.0), closeTo(0.0, 1e-6));
      expect(VrCurves.spring(0.30), greaterThan(1.0)); // underdamped rebound
      expect(VrCurves.spring(4.0), closeTo(1.0, 1e-3)); // settles at 1

      expect(VrCurves.envelope(0.5, 1.0, 5.0), 0.0);
      expect(VrCurves.envelope(3.0, 1.0, 5.0), 1.0);
      expect(VrCurves.envelope(5.5, 1.0, 5.0), 0.0);
    });

    test('VrSeededRandom and vnoise are deterministic', () {
      final a = VrSeededRandom(42);
      final b = VrSeededRandom(42);
      for (var i = 0; i < 10; i++) {
        expect(a.nextDouble(), equals(b.nextDouble()));
      }
      expect(VrCurves.vnoise(2.35), equals(VrCurves.vnoise(2.35)));
      expect(VrCurves.vnoise(2.35), inInclusiveRange(0.0, 1.0));
    });
  });

  group('VrMonotoneSpline & VrVector3Track', () {
    test('preserves monotonicity and avoids overshoot on flat plateaus', () {
      final spline = VrMonotoneSpline([
        (0.0, 0.0),
        (1.0, 10.0),
        (2.0, 10.0), // flat hold
        (3.0, 2.0),
      ]);
      expect(spline.evaluate(0.0), 0.0);
      expect(spline.evaluate(1.0), 10.0);
      expect(spline.evaluate(2.0), 10.0);
      expect(spline.evaluate(3.0), 2.0);

      // During the flat plateau [1.0, 2.0], value must stay exactly 10.0 (no overshoot)
      for (var t = 1.0; t <= 2.0; t += 0.1) {
        expect(spline.evaluate(t), closeTo(10.0, 1e-9));
      }
      // During rising [0.0, 1.0], value must stay within [0, 10]
      for (var t = 0.0; t <= 1.0; t += 0.1) {
        final v = spline.evaluate(t);
        expect(v, inInclusiveRange(0.0, 10.0));
      }
    });

    test('VrVector3Track interpolates 3D waypoints smoothly', () {
      final track = VrVector3Track([
        (0.0, Vector3(0, 0, 0)),
        (2.0, Vector3(4, 2, -6)),
        (4.0, Vector3(4, 2, -10)),
      ]);
      expect(track.evaluate(0.0).storage, equals([0.0, 0.0, 0.0]));
      final mid = track.evaluate(1.0);
      expect(mid.x, closeTo(2.0, 0.5));
      expect(mid.y, closeTo(1.0, 0.25));
      // X and Y are flat between t=2 and t=4
      expect(track.evaluate(3.0).x, closeTo(4.0, 1e-6));
      expect(track.evaluate(3.0).y, closeTo(2.0, 1e-6));
    });
  });

  group('VrBeatTimeline', () {
    test('maps sections, beats, bars, and hit cues accurately', () {
      final timeline = VrBeatTimeline(
        sections: const [
          VrTimelineSection(id: 'intro', startTime: 0.0, bpm: 120.0, beats: 8),
          VrTimelineSection(id: 'chase', startTime: 4.0, bpm: 150.0, beats: 16),
        ],
        hits: const {
          'drop': ('chase', 4.0),
        },
      );

      expect(timeline.sectionById('intro')!.beatDuration, closeTo(0.5, 1e-6));
      expect(timeline.sectionById('chase')!.beatDuration, closeTo(0.4, 1e-6));
      expect(timeline.hitTime('drop'), closeTo(4.0 + 4.0 * 0.4, 1e-6));
      expect(timeline.beatPulseAt(4.0), closeTo(1.0, 1e-6));
      expect(timeline.beatPulseAt(4.2), lessThan(0.5));
    });
  });
}
