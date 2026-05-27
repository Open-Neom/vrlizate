import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('HologramMeshNode', () {
    test('initializes with custom parameters', () {
      final node = HologramMeshNode(
        name: 'test_hologram',
        geometry: SphereGeometry(radius: 1.0),
        hologramColor: const Color(0xFF00FF00),
        flickerSpeed: 8.0,
      );

      expect(node.name, equals('test_hologram'));
      expect(node.flickerSpeed, equals(8.0));
      expect(node.material.color, equals(const Color(0xFF00FF00)));
    });

    test('updates global time tick successfully', () {
      HologramMeshNode.time = 4.2;
      expect(HologramMeshNode.time, equals(4.2));
    });
  });

  group('WifiSensingSystem', () {
    test('initializes as inactive', () {
      final sensing = WifiSensingSystem();
      expect(sensing.isActive, isFalse);
      expect(sensing.trackedSubjects, isEmpty);
      sensing.dispose();
    });

    test('simulated CSI frame structures are correct', () {
      final frame = CsiFrame(
        timestamp: 1000,
        amplitudes: [1.0, 1.2, 0.9, 1.1],
      );

      expect(frame.timestamp, equals(1000));
      expect(frame.amplitudes.length, equals(4));
    });
  });

  group('WifiRadarNode', () {
    test('initializes and configures correctly', () {
      final node = WifiRadarNode(
        name: 'test_radar',
        pulseSpeed: 6.0,
        radarColor: const Color(0xFFFF00FF),
      );

      expect(node.name, equals('test_radar'));
      expect(node.pulseSpeed, equals(6.0));
      expect(node.radarColor, equals(const Color(0xFFFF00FF)));
    });
  });
}
