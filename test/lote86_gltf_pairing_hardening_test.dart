import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/core/network/vr_pairing_payload.dart';
import 'package:vrlizate/loaders/gltf_parser.dart';

void main() {
  group('Lote 86 — vrlizate GltfParser & VrPairingPayload SSRF/quaternion hardening', () {
    test('VrPairingPayload blocks cloud metadata, multicast, Teredo & dot-homoglyphs while keeping LAN/mDNS', () {
      for (final blocked in const <String>[
        '169.254.169.254',
        '100.100.100.200',
        'fd00:ec2::254',
        'metadata.google.internal',
        'metadata.goog',
        'instance-data',
        '0.0.0.0',
        '224.0.0.1',
        '2001:0:4136:e378:8000:63bf:3fff:fdd2',
        '192\u3002168\u30021\u300210',
        'evil.invalid',
      ]) {
        expect(
          () => VrPairingPayload(
            host: blocked,
            port: 8080,
            sessionToken: 'tok-123',
            role: VrDeviceRole.parent,
            transportType: VrTransportType.localSocket,
          ),
          throwsArgumentError,
          reason: 'Expected $blocked to be blocked',
        );
      }

      // Valid LAN & mDNS hosts must still pass
      final valid = VrPairingPayload(
        host: 'visor.local',
        port: 8080,
        sessionToken: 'tok-123',
        role: VrDeviceRole.parent,
        transportType: VrTransportType.localSocket,
      );
      expect(valid.host, equals('visor.local'));
    });

    test('GltfParser rejects invalid GLB version/chunk type and replaces zero-norm quaternions with identity', () {
      // Bad GLB version (version = 1)
      final badVersion = ByteData(20);
      badVersion.setUint32(0, 0x46546C67, Endian.little);
      badVersion.setUint32(4, 1, Endian.little);
      badVersion.setUint32(8, 20, Endian.little);
      badVersion.setUint32(12, 0, Endian.little);
      badVersion.setUint32(16, 0x4E4F534A, Endian.little);
      expect(
        () => GltfParser.parseGlb(badVersion.buffer.asUint8List()),
        throwsFormatException,
      );

      // Zero-norm rotation quaternion [0,0,0,0] falls back to identity without NaN
      final result = GltfParser.parseJson(
        jsonEncode(<String, Object?>{
          'asset': <String, String>{'version': '2.0'},
          'nodes': <Object?>[
            <String, Object?>{
              'name': 'node\u202E_spoof',
              'rotation': <double>[0, 0, 0, 0],
            },
          ],
          'scenes': <Object?>[
            <String, Object?>{'nodes': <int>[0]},
          ],
          'scene': 0,
        }),
      );
      final node = result.root.children.single;
      expect(node.name, equals('node_spoof'));
      expect(node.transform.rotation.w, equals(1.0));
      expect(node.transform.localMatrix.storage.every((v) => v.isFinite), isTrue);

      // Coincident lookAt(position) must not poison localMatrix with NaN
      node.transform.lookAt(node.transform.position.clone());
      expect(node.transform.localMatrix.storage.every((v) => v.isFinite), isTrue);
    });
  });
}
