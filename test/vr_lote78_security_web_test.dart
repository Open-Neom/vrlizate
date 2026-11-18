import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/core/input/vr_input_event_bus.dart';
import 'package:vrlizate/core/network/vr_controller_protocol.dart';
import 'package:vrlizate/core/network/vr_pairing_payload.dart';
import 'package:vrlizate/loaders/gltf_parser.dart';
import 'package:vrlizate/scene/node.dart';

void main() {
  group('Lote 78 — Node Scene Graph Cycle & Non-Finite Guards', () {
    test('rejects self-parenting and ancestor cycles, and ignores non-finite dt', () {
      final root = Node(name: 'root');
      final child = Node(name: 'child');
      final grandChild = Node(name: 'grandChild');

      root.addChild(child);
      child.addChild(grandChild);

      expect(() => root.addChild(root), throwsArgumentError);
      expect(() => grandChild.addChild(root), throwsArgumentError);

      var updatedDt = -1.0;
      final probe = _ProbeNode((dt) => updatedDt = dt);
      root.addChild(probe);

      root.update(double.nan);
      root.update(double.infinity);
      root.update(-0.5);
      expect(updatedDt, -1.0);

      root.update(0.016);
      expect(updatedDt, closeTo(0.016, 1e-9));
    });
  });

  group('Lote 78 — GltfParser Truncated, Cyclic & Out-of-Bounds Defense', () {
    test('rejects truncated GLB headers, negative indices, cyclic nodes, and shared mesh re-parenting cleanly', () {
      expect(
        () => GltfParser.parseGlb(Uint8List.fromList(<int>[1, 2])),
        throwsFormatException,
      );
      expect(
        () => GltfParser.parseGlb(Uint8List(12)),
        throwsFormatException,
      );
      expect(
        () => GltfParser.parseJson('[]'),
        throwsFormatException,
      );

      final cyclicGltf = jsonEncode(<String, Object?>{
        'scene': 0,
        'scenes': <Object?>[
          <String, Object?>{
            'nodes': <int>[0],
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{
            'name': 'n0',
            'children': <int>[1],
          },
          <String, Object?>{
            'name': 'n1',
            'children': <int>[0],
          },
        ],
      });
      expect(
        () => GltfParser.parseJson(cyclicGltf),
        throwsFormatException,
      );

      final negativeAccessorGltf = jsonEncode(<String, Object?>{
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, int>{'POSITION': -1},
              },
            ],
          },
        ],
      });
      expect(
        () => GltfParser.parseJson(negativeAccessorGltf),
        throwsFormatException,
      );

      // Shared mesh referenced by two distinct scene nodes must clone rather than steal parent.
      final posFloats = Float32List.fromList(<double>[
        0, 0, 0,
        1, 0, 0,
        0, 1, 0,
      ]);
      final bin = posFloats.buffer.asUint8List();
      final sharedMeshGltf = jsonEncode(<String, Object?>{
        'scene': 0,
        'scenes': <Object?>[
          <String, Object?>{
            'nodes': <int>[0, 1],
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{'name': 'left', 'mesh': 0},
          <String, Object?>{'name': 'right', 'mesh': 0},
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'name': 'tri',
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, int>{'POSITION': 0},
              },
            ],
          },
        ],
        'accessors': <Object?>[
          <String, Object?>{
            'bufferView': 0,
            'componentType': 5126,
            'count': 3,
            'type': 'VEC3',
          },
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 0,
            'byteOffset': 0,
            'byteLength': bin.length,
          },
        ],
      });
      final parsedRoot =
          GltfParser.parseJson(sharedMeshGltf, binaryBuffer: bin).root;
      expect(parsedRoot.children, hasLength(2));
      expect(parsedRoot.children[0].children, hasLength(1));
      expect(parsedRoot.children[1].children, hasLength(1));
    });
  });

  group('Lote 78 — VrControllerProtocol & VrPairingPayload Hardening', () {
    test('VrControllerMessageCodec blocks oversized frames, prototype keys, non-finite numbers, and overflow timestamps', () {
      const codec = VrControllerMessageCodec();
      expect(
        () => codec.decode(' ' * (VrControllerMessageCodec.maxEncodedLength + 1)),
        throwsFormatException,
      );
      expect(
        () => codec.decode(
          '{"kind":"input","event":{"type":"select","source":"remotePhone","active":true,"timestampUs":1,"data":{"__proto__":{"polluted":true}}}}',
        ),
        throwsFormatException,
      );

      final extremeSnap = VrInputEventSnapshot.fromJson(<String, dynamic>{
        'type': 'select',
        'source': 'remotePhone',
        'active': true,
        'timestampUs': 9007199254740991,
      });
      // 9007199254740991 us (~9.0e12 ms) is within safe DateTime epoch; verify it converts cleanly.
      expect(extremeSnap.toEvent().timestampMicrosecondsSinceEpoch, 9007199254740991);

      expect(
        () => VrInputEventSnapshot.fromEvent(
          VrInputEvent(
            type: VrInputType.select,
            source: VrInputSource.remotePhone,
            data: <String, dynamic>{'bad': double.nan},
          ),
        ),
        throwsArgumentError,
      );
    });

    test('VrPairingPayload blocks control/Bidi chars and host delimiters while keeping spaces/+ in tokens', () {
      final ok = VrPairingPayload(
        host: 'visor.local',
        port: 8765,
        sessionToken: 'token with spaces/+',
        role: VrDeviceRole.child,
        transportType: VrTransportType.localSocket,
      );
      expect(VrPairingPayload.fromUri(ok.toUri()), ok);

      expect(
        () => VrPairingPayload(
          host: 'evil.com/path',
          port: 8080,
          sessionToken: 'tok',
          role: VrDeviceRole.parent,
          transportType: VrTransportType.localSocket,
        ),
        throwsArgumentError,
      );
      expect(
        () => VrPairingPayload(
          host: '192.168.1.10',
          port: 8080,
          sessionToken: 'tok\u202Een',
          role: VrDeviceRole.parent,
          transportType: VrTransportType.localSocket,
        ),
        throwsArgumentError,
      );
    });
  });
}

class _ProbeNode extends Node {
  final void Function(double dt) onTick;
  _ProbeNode(this.onTick) : super(name: 'probe');

  @override
  void onUpdate(double dt) => onTick(dt);
}
