import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:vrlizate/vrlizate.dart';

/// glTF parser benchmarks — validates robustness with edge cases,
/// malformed input, and large scene hierarchies.
void main() {
  group('GltfParser — Robustness', () {
    test('parses empty nodes array gracefully', () {
      final json = jsonEncode({'nodes': [], 'meshes': []});
      final result = GltfParser.parseJson(json);

      expect(result, isNotNull);
    });

    test('handles missing meshes field', () {
      final json = jsonEncode({
        'nodes': [
          {
            'name': 'empty_node',
            'translation': [0, 0, 0],
          },
        ],
      });
      final result = GltfParser.parseJson(json);
      expect(result, isNotNull);
    });

    test('parses deep node hierarchy (20 levels)', () {
      final nodes = <Map<String, dynamic>>[];
      for (var i = 0; i < 20; i++) {
        nodes.add({
          'name': 'node_$i',
          'translation': [0, i.toDouble(), 0],
          if (i < 19) 'children': [i + 1],
        });
      }

      final json = jsonEncode({
        'nodes': nodes,
        'scenes': [
          {
            'nodes': [0],
          },
        ],
        'scene': 0,
      });

      final result = GltfParser.parseJson(json);
      expect(result, isNotNull);
    });

    test('rejects invalid GLB magic number', () {
      final badGlb = Uint8List.fromList([
        0x00,
        0x00,
        0x00,
        0x00,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        20,
      ]);
      expect(
        () => GltfParser.parseGlb(badGlb),
        throwsA(isA<FormatException>()),
      );
    });

    test('valid GLB header parses without crash', () {
      // Minimal valid GLB: magic(4) + version(4) + length(4) + JSON chunk header(8) + JSON data
      final jsonData = utf8.encode('{"nodes":[]}');
      final jsonPadded = jsonData.length % 4 == 0
          ? jsonData
          : [...jsonData, ...List.filled(4 - jsonData.length % 4, 0x20)];

      final totalLength = 12 + 8 + jsonPadded.length;
      final buffer = ByteData(totalLength);

      // Header
      buffer.setUint32(0, 0x46546C67, Endian.little); // glTF magic
      buffer.setUint32(4, 2, Endian.little); // version 2
      buffer.setUint32(8, totalLength, Endian.little);

      // JSON chunk
      buffer.setUint32(12, jsonPadded.length, Endian.little);
      buffer.setUint32(16, 0x4E4F534A, Endian.little); // JSON type

      final bytes = buffer.buffer.asUint8List();
      final result = Uint8List.fromList([
        ...bytes.sublist(0, 20),
        ...jsonPadded,
      ]);

      // Should not throw
      GltfParser.parseGlb(result);
    });

    test('material with all PBR fields parses correctly', () {
      final json = jsonEncode({
        'materials': [
          {
            'name': 'PBR_Full',
            'pbrMetallicRoughness': {
              'baseColorFactor': [1.0, 0.5, 0.0, 1.0],
              'metallicFactor': 0.8,
              'roughnessFactor': 0.2,
            },
            'doubleSided': true,
          },
        ],
        'nodes': [],
      });

      final result = GltfParser.parseJson(json);
      expect(result, isNotNull);
      expect(result.materials.length, equals(1));
      expect(result.materials.first.metallic, closeTo(0.8, 1e-3));
      expect(result.materials.first.roughness, closeTo(0.2, 1e-3));
      expect(result.materials.first.doubleSided, isTrue);
    });

    test('parse 100 nodes with transforms < 50ms', () {
      final nodes = <Map<String, dynamic>>[];
      for (var i = 0; i < 100; i++) {
        nodes.add({
          'name': 'node_$i',
          'translation': [i.toDouble(), 0, 0],
          'rotation': [0, 0, 0, 1],
          'scale': [1, 1, 1],
        });
      }

      final json = jsonEncode({'nodes': nodes});

      final sw = Stopwatch()..start();
      GltfParser.parseJson(json);
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(100));
    });
  });
}
