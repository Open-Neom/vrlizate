import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('WifiRttPositioning', () {
    final anchors = [
      WifiRttAnchor(id: 'ap-1', position: Vector3(0, 0, 0)),
      WifiRttAnchor(id: 'ap-2', position: Vector3(10, 0, 0)),
      WifiRttAnchor(id: 'ap-3', position: Vector3(0, 10, 0)),
      WifiRttAnchor(id: 'ap-4', position: Vector3(10, 10, 0)),
    ];

    WifiRttPositioning buildSystem() {
      final system = WifiRttPositioning(smoothing: 1.0);
      for (final a in anchors) {
        system.addAnchor(a);
      }
      return system;
    }

    RttMeasurement measure(
      WifiRttAnchor anchor,
      Vector3 device, [
      double noise = 0,
      double? stdDev,
    ]) {
      final d = (device - anchor.position).length + noise;
      return RttMeasurement(
        anchorId: anchor.id,
        distanceMeters: d,
        stdDevMeters: stdDev,
      );
    }

    test('trilaterates a known position with clean measurements', () async {
      final system = buildSystem();
      final device = Vector3(3, 4, 0);

      RttPosition? fix;
      final sub = system.onPosition.listen((p) => fix = p);

      for (final a in anchors) {
        system.feedMeasurement(measure(a, device));
      }
      await Future.delayed(Duration.zero);

      expect(fix, isNotNull);
      expect((fix!.position - device).length, lessThan(0.05));
      expect(fix!.anchorsUsed, 4);
      expect(fix!.residualRms, lessThan(0.01));

      await sub.cancel();
      system.dispose();
    });

    test(
      'recovers a good fix despite one noisy anchor (outlier rejection)',
      () async {
        final system = buildSystem();
        final device = Vector3(5, 5, 0);

        RttPosition? fix;
        final sub = system.onPosition.listen((p) => fix = p);

        system.feedMeasurement(measure(anchors[0], device));
        system.feedMeasurement(measure(anchors[1], device));
        system.feedMeasurement(measure(anchors[2], device));
        // Grossly wrong measurement from the fourth anchor.
        system.feedMeasurement(measure(anchors[3], device, 6.0));
        await Future.delayed(Duration.zero);

        expect(fix, isNotNull);
        expect((fix!.position - device).length, lessThan(1.0));

        await sub.cancel();
        system.dispose();
      },
    );

    test('does not publish a fix with fewer than 3 anchors', () async {
      final system = buildSystem();
      var fixes = 0;
      final sub = system.onPosition.listen((_) => fixes++);

      final device = Vector3(2, 2, 0);
      system.feedMeasurement(measure(anchors[0], device));
      system.feedMeasurement(measure(anchors[1], device));
      await Future.delayed(Duration.zero);

      expect(fixes, 0);
      expect(system.lastPosition, isNull);

      await sub.cancel();
      system.dispose();
    });

    test('ignores measurements from unknown anchors', () async {
      final system = buildSystem();
      var fixes = 0;
      final sub = system.onPosition.listen((_) => fixes++);

      system.feedMeasurement(
        RttMeasurement(anchorId: 'rogue-ap', distanceMeters: 2.0),
      );
      await Future.delayed(Duration.zero);

      expect(fixes, 0);

      await sub.cancel();
      system.dispose();
    });

    test('drops stale measurements outside the measurement window', () async {
      final system = WifiRttPositioning(
        measurementWindow: const Duration(milliseconds: 500),
        smoothing: 1.0,
      );
      for (final a in anchors) {
        system.addAnchor(a);
      }

      final device = Vector3(6, 3, 0);
      final old = DateTime(2026, 1, 1);
      // Two old measurements.
      system.feedMeasurement(
        RttMeasurement(
          anchorId: 'ap-1',
          distanceMeters: (device - anchors[0].position).length,
          timestamp: old,
        ),
      );
      system.feedMeasurement(
        RttMeasurement(
          anchorId: 'ap-2',
          distanceMeters: (device - anchors[1].position).length,
          timestamp: old,
        ),
      );

      // One fresh measurement: the stale ones get pruned, no fix possible.
      var fixes = 0;
      final sub = system.onPosition.listen((_) => fixes++);
      system.feedMeasurement(
        RttMeasurement(
          anchorId: 'ap-3',
          distanceMeters: (device - anchors[2].position).length,
          timestamp: old.add(const Duration(seconds: 2)),
        ),
      );
      await Future.delayed(Duration.zero);
      expect(fixes, 0);

      await sub.cancel();
      system.dispose();
    });

    test('weights favor low-stdDev measurements', () async {
      final system = buildSystem();
      final device = Vector3(4, 6, 0);

      RttPosition? fix;
      final sub = system.onPosition.listen((p) => fix = p);

      // Precise anchors.
      system.feedMeasurement(measure(anchors[0], device, 0, 0.3));
      system.feedMeasurement(measure(anchors[1], device, 0, 0.3));
      system.feedMeasurement(measure(anchors[2], device, 0, 0.3));
      // Imprecise anchor with moderate error: high stdDev downweights it.
      system.feedMeasurement(measure(anchors[3], device, 1.5, 5.0));
      await Future.delayed(Duration.zero);

      expect(fix, isNotNull);
      expect((fix!.position - device).length, lessThan(1.0));

      await sub.cancel();
      system.dispose();
    });

    test('smoothing blends consecutive fixes', () async {
      final system = WifiRttPositioning(smoothing: 0.5);
      for (final a in anchors) {
        system.addAnchor(a);
      }

      final positions = <RttPosition>[];
      final sub = system.onPosition.listen(positions.add);

      final t0 = DateTime(2026, 1, 1);
      // Fix 1 at (3,4,0).
      final p1 = Vector3(3, 4, 0);
      for (final a in anchors) {
        system.feedMeasurement(
          RttMeasurement(
            anchorId: a.id,
            distanceMeters: (p1 - a.position).length,
            timestamp: t0,
          ),
        );
      }

      // Move to (5,4,0) — 2 m along x.
      final p2 = Vector3(5, 4, 0);
      for (final a in anchors) {
        system.feedMeasurement(
          RttMeasurement(
            anchorId: a.id,
            distanceMeters: (p2 - a.position).length,
            timestamp: t0.add(const Duration(milliseconds: 500)),
          ),
        );
      }
      await Future.delayed(Duration.zero);

      expect(positions.length, greaterThanOrEqualTo(2));
      final first = positions.first.position;
      final last = positions.last.position;
      expect((first - p1).length, lessThan(0.1));
      // Smoothed: should be between p1 and p2, not a jump to p2.
      expect(last.x, greaterThan(first.x));
      expect(last.x, lessThan(p2.x));

      await sub.cancel();
      system.dispose();
    });

    test(
      'trilateration math: 3 anchors on a circle recover the center',
      () async {
        final system = WifiRttPositioning(smoothing: 1.0);
        final center = Vector3(5, 5, 0);
        const radius = 4.0;
        for (var i = 0; i < 3; i++) {
          final angle = i * 2 * math.pi / 3;
          system.addAnchor(
            WifiRttAnchor(
              id: 'ap-$i',
              position:
                  center +
                  Vector3(
                    radius * math.cos(angle),
                    radius * math.sin(angle),
                    0,
                  ),
            ),
          );
        }

        RttPosition? fix;
        final sub = system.onPosition.listen((p) => fix = p);
        for (var i = 0; i < 3; i++) {
          system.feedMeasurement(
            RttMeasurement(anchorId: 'ap-$i', distanceMeters: radius),
          );
        }
        await Future.delayed(Duration.zero);

        expect(fix, isNotNull);
        expect((fix!.position - center).length, lessThan(0.05));

        await sub.cancel();
        system.dispose();
      },
    );
  });
}
