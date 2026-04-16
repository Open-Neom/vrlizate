import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('GltfParser', () {
    test('parses minimal valid glTF JSON', () {
      final json = jsonEncode({
        'asset': {'version': '2.0'},
        'scenes': [{'nodes': [0]}],
        'scene': 0,
        'nodes': [
          {'name': 'TestNode', 'translation': [1, 2, 3]},
        ],
      });

      final result = GltfParser.parseJson(json);
      expect(result.root.childCount, equals(1));

      final node = result.root.children.first;
      expect(node.name, equals('TestNode'));
      expect(node.transform.position.x, closeTo(1, 1e-4));
      expect(node.transform.position.y, closeTo(2, 1e-4));
      expect(node.transform.position.z, closeTo(3, 1e-4));
    });

    test('parses node hierarchy', () {
      final json = jsonEncode({
        'asset': {'version': '2.0'},
        'scenes': [{'nodes': [0]}],
        'scene': 0,
        'nodes': [
          {'name': 'parent', 'children': [1]},
          {'name': 'child'},
        ],
      });

      final result = GltfParser.parseJson(json);
      final parent = result.root.findChild('parent');
      expect(parent, isNotNull);
      expect(parent!.childCount, equals(1));
      expect(parent.children.first.name, equals('child'));
    });

    test('parses node rotation as quaternion', () {
      final json = jsonEncode({
        'asset': {'version': '2.0'},
        'scenes': [{'nodes': [0]}],
        'scene': 0,
        'nodes': [
          {'name': 'rotated', 'rotation': [0, 0.707, 0, 0.707]},
        ],
      });

      final result = GltfParser.parseJson(json);
      final node = result.root.findChild('rotated');
      expect(node, isNotNull);
      expect(node!.transform.rotation.length, closeTo(1, 1e-3));
    });

    test('parses node scale', () {
      final json = jsonEncode({
        'asset': {'version': '2.0'},
        'scenes': [{'nodes': [0]}],
        'scene': 0,
        'nodes': [
          {'name': 'scaled', 'scale': [2, 3, 4]},
        ],
      });

      final result = GltfParser.parseJson(json);
      final node = result.root.findChild('scaled');
      expect(node!.transform.scale.x, closeTo(2, 1e-4));
      expect(node.transform.scale.y, closeTo(3, 1e-4));
    });

    test('parses materials with PBR', () {
      final json = jsonEncode({
        'asset': {'version': '2.0'},
        'scenes': [{'nodes': []}],
        'scene': 0,
        'nodes': [],
        'materials': [
          {
            'pbrMetallicRoughness': {
              'baseColorFactor': [1, 0, 0, 1],
              'metallicFactor': 0.8,
              'roughnessFactor': 0.2,
            },
            'doubleSided': true,
          }
        ],
      });

      final result = GltfParser.parseJson(json);
      expect(result.materials.length, equals(1));
      expect(result.materials[0].metallic, closeTo(0.8, 1e-4));
      expect(result.materials[0].roughness, closeTo(0.2, 1e-4));
      expect(result.materials[0].doubleSided, isTrue);
      expect(result.materials[0].color.red, equals(255));
    });

    test('handles empty glTF gracefully', () {
      final json = jsonEncode({
        'asset': {'version': '2.0'},
      });

      final result = GltfParser.parseJson(json);
      expect(result.root.childCount, equals(0));
      expect(result.meshes, isEmpty);
      expect(result.materials, isEmpty);
    });

    test('GLB magic number validation', () {
      final badGlb = Uint8List.fromList([0, 0, 0, 0]); // Wrong magic
      expect(() => GltfParser.parseGlb(badGlb), throwsFormatException);
    });

    test('handles missing optional fields', () {
      final json = jsonEncode({
        'asset': {'version': '2.0'},
        'scenes': [{'nodes': [0]}],
        'scene': 0,
        'nodes': [{}], // No name, no transform
      });

      final result = GltfParser.parseJson(json);
      expect(result.root.childCount, equals(1));
      expect(result.root.children.first.name, equals(''));
    });
  });
}
