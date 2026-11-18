import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:vector_math/vector_math.dart';

import '../scene/geometry.dart';
import '../scene/node.dart';
import '../scene/material.dart';
import '../scene/mesh.dart';

/// Lightweight glTF 2.0 JSON parser for vrlizate.
/// Handles meshes, materials, and node hierarchy.
/// Does NOT handle textures (use PBRMaterial.colorMap for that).
///
/// For full glTF support (animations, skins, cameras), use a dedicated
/// glTF package as an optional dependency.
class GltfParser {
  static const int maxGlbBytes = 64 * 1024 * 1024;
  static const int maxJsonChars = 16 * 1024 * 1024;
  static const int maxAccessorElements = 1000000;
  static const int maxSceneGraphItems = 65536;

  static final RegExp _sceneNameControlOrBidi = RegExp(
    r'[\x00-\x1F\x7F-\x9F\u0085\u061C\u200B-\u200F\u2028-\u202E\u2060\u2066-\u2069\uFEFF]',
  );

  static String _sanitizeSceneName(Object? raw, {String fallback = ''}) {
    if (raw is! String) return fallback;
    final cleaned = raw.replaceAll(_sceneNameControlOrBidi, '').trim();
    if (cleaned.isEmpty) return fallback;
    if (cleaned.length <= 256) return cleaned;
    var end = 256;
    final lastCode = cleaned.codeUnitAt(end - 1);
    if (lastCode >= 0xD800 && lastCode <= 0xDBFF) end--;
    return end <= 0 ? fallback : cleaned.substring(0, end);
  }

  /// Parses a glTF JSON string and returns the root node.
  static GltfResult parseJson(String jsonString, {Uint8List? binaryBuffer}) {
    if (jsonString.length > maxJsonChars) {
      throw const FormatException('glTF JSON exceeds maximum allowed size');
    }
    if (binaryBuffer != null && binaryBuffer.length > maxGlbBytes) {
      throw const FormatException('glTF binary buffer exceeds maximum size');
    }
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map) {
      throw const FormatException('glTF root must be a JSON object');
    }
    return _parse(Map<String, dynamic>.from(decoded), binaryBuffer);
  }

  /// Parses a GLB binary buffer.
  static GltfResult parseGlb(Uint8List glbData) {
    if (glbData.length < 4) {
      throw const FormatException('Truncated GLB header');
    }
    if (glbData.length > maxGlbBytes) {
      throw const FormatException('GLB exceeds maximum allowed size');
    }
    // GLB header: magic(4) + version(4) + length(4) = 12 bytes
    final magic = ByteData.sublistView(
      glbData,
      0,
      4,
    ).getUint32(0, Endian.little);
    if (magic != 0x46546C67) {
      throw const FormatException('Invalid GLB magic number');
    }
    if (glbData.length < 20) {
      throw const FormatException('Truncated GLB header');
    }
    final version = ByteData.sublistView(
      glbData,
      4,
      8,
    ).getUint32(0, Endian.little);
    if (version != 2) {
      throw FormatException('Unsupported GLB version: $version');
    }

    // Chunk 0: JSON
    final jsonLength = ByteData.sublistView(
      glbData,
      12,
      16,
    ).getUint32(0, Endian.little);
    final jsonChunkType = ByteData.sublistView(
      glbData,
      16,
      20,
    ).getUint32(0, Endian.little);
    if (jsonChunkType != 0x4E4F534A) {
      throw const FormatException('Invalid GLB first chunk type; expected JSON');
    }
    if (jsonLength > maxJsonChars || jsonLength > glbData.length - 20) {
      throw const FormatException('Invalid or truncated GLB JSON chunk');
    }
    final jsonString = utf8.decode(glbData.sublist(20, 20 + jsonLength));

    // Chunk 1: Binary (optional)
    Uint8List? binBuffer;
    final binOffset = 20 + jsonLength;
    if (glbData.length > binOffset) {
      if (glbData.length < binOffset + 8) {
        throw const FormatException('Truncated GLB binary chunk header');
      }
      final binLength = ByteData.sublistView(
        glbData,
        binOffset,
        binOffset + 4,
      ).getUint32(0, Endian.little);
      final binChunkType = ByteData.sublistView(
        glbData,
        binOffset + 4,
        binOffset + 8,
      ).getUint32(0, Endian.little);
      if (binLength > glbData.length - (binOffset + 8)) {
        throw const FormatException('Truncated GLB binary chunk payload');
      }
      if (binChunkType == 0x004E4942) {
        binBuffer = glbData.sublist(binOffset + 8, binOffset + 8 + binLength);
      }
    }

    final decoded = jsonDecode(jsonString);
    if (decoded is! Map) {
      throw const FormatException('GLB JSON chunk must be an object');
    }
    return _parse(Map<String, dynamic>.from(decoded), binBuffer);
  }

  static GltfResult _parse(Map<String, dynamic> gltf, Uint8List? buffer) {
    final meshes = <MeshNode>[];

    // Parse materials
    final materials = <VRMaterial>[];
    final rawMatList = gltf['materials'];
    final matList = rawMatList is List ? rawMatList : const <dynamic>[];
    if (matList.length > maxSceneGraphItems) {
      throw const FormatException('Too many glTF materials');
    }
    for (final mat in matList) {
      if (mat is! Map) {
        throw const FormatException('glTF material must be an object');
      }
      final m = Map<String, dynamic>.from(mat);
      final rawPbr = m['pbrMetallicRoughness'];
      final pbr = rawPbr is Map
          ? Map<String, dynamic>.from(rawPbr)
          : const <String, dynamic>{};
      final rawBaseColor = pbr['baseColorFactor'];
      final baseColor = rawBaseColor is List ? rawBaseColor : null;
      if (baseColor != null && baseColor.length < 4) {
        throw const FormatException(
          'glTF baseColorFactor must contain 4 numeric components',
        );
      }

      materials.add(
        VRMaterial(
          color: baseColor != null
              ? Color.fromARGB(
                  _colorChannel(baseColor[3]),
                  _colorChannel(baseColor[0]),
                  _colorChannel(baseColor[1]),
                  _colorChannel(baseColor[2]),
                )
              : const Color(0xFFCCCCCC),
          metallic: _finiteDouble(pbr['metallicFactor'], 0).clamp(0.0, 1.0),
          roughness: _finiteDouble(pbr['roughnessFactor'], 1).clamp(0.0, 1.0),
          doubleSided: m['doubleSided'] == true,
        ),
      );
    }

    // Parse meshes
    final rawMeshList = gltf['meshes'];
    final meshList = rawMeshList is List ? rawMeshList : const <dynamic>[];
    final rawAccessors = gltf['accessors'];
    final accessors = rawAccessors is List ? rawAccessors : const <dynamic>[];
    final rawBufferViews = gltf['bufferViews'];
    final bufferViews = rawBufferViews is List
        ? rawBufferViews
        : const <dynamic>[];
    if (meshList.length > maxSceneGraphItems ||
        accessors.length > maxSceneGraphItems ||
        bufferViews.length > maxSceneGraphItems) {
      throw const FormatException('glTF scene exceeds maximum element count');
    }

    for (final mesh in meshList) {
      if (mesh is! Map) {
        throw const FormatException('glTF mesh must be an object');
      }
      final meshMap = Map<String, dynamic>.from(mesh);
      final rawPrimitives = meshMap['primitives'];
      final primitives = rawPrimitives is List
          ? rawPrimitives
          : const <dynamic>[];
      if (primitives.length > maxSceneGraphItems) {
        throw const FormatException('Too many primitives in glTF mesh');
      }

      for (final prim in primitives) {
        if (prim is! Map) {
          throw const FormatException('glTF primitive must be an object');
        }
        final p = Map<String, dynamic>.from(prim);
        final rawAttrs = p['attributes'];
        final attrs = rawAttrs is Map
            ? Map<String, dynamic>.from(rawAttrs)
            : const <String, dynamic>{};

        // Extract vertex positions
        final posAccessor = _optionalIndex(attrs['POSITION'], accessors.length);
        final vertices = posAccessor != null && buffer != null
            ? _readVec3Accessor(accessors[posAccessor], bufferViews, buffer)
            : <Vector3>[Vector3.zero()];

        // Extract normals
        final normAccessor = _optionalIndex(attrs['NORMAL'], accessors.length);
        final normals = normAccessor != null && buffer != null
            ? _readVec3Accessor(accessors[normAccessor], bufferViews, buffer)
            : null;
        if (normals != null && normals.length != vertices.length) {
          throw const FormatException(
            'glTF normal count must match vertex count',
          );
        }

        // Extract indices
        final idxAccessor = _optionalIndex(p['indices'], accessors.length);
        final indices = idxAccessor != null && buffer != null
            ? _readIndexAccessor(accessors[idxAccessor], bufferViews, buffer)
            : List.generate(vertices.length, (i) => i);

        if (vertices.isNotEmpty) {
          for (final idx in indices) {
            if (idx < 0 || idx >= vertices.length) {
              throw const FormatException(
                'glTF primitive index exceeds vertex count',
              );
            }
          }
        }

        // Material
        final matIdx = _optionalIndex(p['material'], materials.length);
        final material = matIdx != null ? materials[matIdx] : VRMaterial();

        final geometry = Geometry(
          vertices: vertices,
          normals: normals,
          indices: indices,
        );

        final rawMeshName = meshMap['name'];
        final meshNode = MeshNode(
          name: _sanitizeSceneName(rawMeshName, fallback: 'mesh'),
          geometry: geometry,
          material: material,
        );
        meshes.add(meshNode);
      }
    }

    // Parse node hierarchy
    final rawNodeList = gltf['nodes'];
    final nodeList = rawNodeList is List ? rawNodeList : const <dynamic>[];
    if (nodeList.length > maxSceneGraphItems) {
      throw const FormatException('Too many glTF nodes');
    }
    final parsedNodes = <Node>[];

    for (final n in nodeList) {
      if (n is! Map) {
        throw const FormatException('glTF node must be an object');
      }
      final nd = Map<String, dynamic>.from(n);
      final rawName = nd['name'];
      final node = Node(name: _sanitizeSceneName(rawName));

      // Transform
      final translation = nd['translation'];
      if (translation != null) {
        final t = _readFixedNumberList(translation, 3, 'translation');
        node.transform.position = Vector3(t[0], t[1], t[2]);
      }

      final rotation = nd['rotation'];
      if (rotation != null) {
        final r = _readFixedNumberList(rotation, 4, 'rotation');
        final normSq = r[0] * r[0] + r[1] * r[1] + r[2] * r[2] + r[3] * r[3];
        node.transform.rotation = normSq.isFinite && normSq >= 1e-12
            ? Quaternion(r[0], r[1], r[2], r[3])
            : Quaternion.identity();
      }

      final scale = nd['scale'];
      if (scale != null) {
        final s = _readFixedNumberList(scale, 3, 'scale');
        node.transform.scale = Vector3(s[0], s[1], s[2]);
      }

      // Attach mesh if referenced (clone if already attached to another node)
      final meshIdx = _optionalIndex(nd['mesh'], meshes.length);
      if (meshIdx != null) {
        final targetMesh = meshes[meshIdx];
        if (targetMesh.parent == null) {
          node.addChild(targetMesh);
        } else {
          node.addChild(
            MeshNode(
              name: targetMesh.name,
              geometry: targetMesh.geometry,
              material: targetMesh.material,
            ),
          );
        }
      }

      parsedNodes.add(node);
    }

    // Build hierarchy (rejecting cycles/invalid child indices)
    for (var i = 0; i < nodeList.length; i++) {
      final nd = Map<String, dynamic>.from(nodeList[i] as Map);
      final children = nd['children'];
      if (children is List) {
        for (final rawChildIdx in children) {
          final childIdx = _optionalIndex(rawChildIdx, parsedNodes.length);
          if (childIdx == null) continue;
          final childNode = parsedNodes[childIdx];
          if (identical(childNode, parsedNodes[i])) {
            throw const FormatException('glTF node cannot reference itself');
          }
          if (childNode.parent != null) {
            throw const FormatException('glTF nodes must form a strict tree');
          }
          try {
            parsedNodes[i].addChild(childNode);
          } on ArgumentError {
            throw const FormatException('Cycle detected in glTF node graph');
          }
        }
      }
    }

    // Root node
    final root = Node(name: 'gltf_root');
    final rawSceneIdx = gltf['scene'];
    final sceneIdx =
        rawSceneIdx is int && rawSceneIdx.isFinite && rawSceneIdx >= 0
        ? rawSceneIdx
        : 0;
    final rawScenes = gltf['scenes'];
    final scenes = rawScenes is List ? rawScenes : const <dynamic>[];
    if (sceneIdx < scenes.length && scenes[sceneIdx] is Map) {
      final sceneMap = Map<String, dynamic>.from(scenes[sceneIdx] as Map);
      final rawSceneNodes = sceneMap['nodes'];
      final sceneNodes = rawSceneNodes is List
          ? rawSceneNodes
          : const <dynamic>[];
      for (final rawNodeIdx in sceneNodes) {
        final nodeIdx = _optionalIndex(rawNodeIdx, parsedNodes.length);
        if (nodeIdx != null && parsedNodes[nodeIdx].parent == null) {
          root.addChild(parsedNodes[nodeIdx]);
        }
      }
    } else {
      for (final node in parsedNodes) {
        if (node.parent == null) root.addChild(node);
      }
    }

    return GltfResult(root: root, meshes: meshes, materials: materials);
  }

  static int _colorChannel(Object? raw) {
    if (raw is! num || !raw.isFinite) {
      throw const FormatException('glTF color component must be finite');
    }
    return (raw.toDouble().clamp(0.0, 1.0) * 255.0).round();
  }

  static double _finiteDouble(Object? raw, double fallback) {
    if (raw == null) return fallback;
    if (raw is! num || !raw.isFinite) {
      throw const FormatException('glTF numeric field must be finite');
    }
    return raw.toDouble();
  }

  static int? _optionalIndex(Object? raw, int upperBoundExclusive) {
    if (raw == null) return null;
    if (raw is! int || !raw.isFinite || raw < 0 || raw >= upperBoundExclusive) {
      throw const FormatException('glTF index out of bounds');
    }
    return raw;
  }

  static List<double> _readFixedNumberList(
    Object? raw,
    int expectedLength,
    String fieldName,
  ) {
    if (raw is! List || raw.length != expectedLength) {
      throw FormatException(
        'glTF "$fieldName" must have $expectedLength components',
      );
    }
    final out = <double>[];
    for (final item in raw) {
      if (item is! num || !item.isFinite) {
        throw FormatException('glTF "$fieldName" components must be finite');
      }
      out.add(item.toDouble());
    }
    return out;
  }

  static int _nonNegInt(Object? raw, {int fallback = 0}) {
    if (raw == null) return fallback;
    if (raw is! int || !raw.isFinite || raw < 0) {
      throw const FormatException('glTF byte offset/count must be >= 0');
    }
    return raw;
  }

  static List<Vector3> _readVec3Accessor(
    dynamic accessor,
    List<dynamic> bufferViews,
    Uint8List buffer,
  ) {
    if (accessor is! Map) {
      throw const FormatException('glTF accessor must be an object');
    }
    final acc = Map<String, dynamic>.from(accessor);
    final viewIdx = _optionalIndex(acc['bufferView'], bufferViews.length);
    if (viewIdx == null || bufferViews[viewIdx] is! Map) {
      throw const FormatException('Invalid glTF accessor bufferView');
    }
    final view = Map<String, dynamic>.from(bufferViews[viewIdx] as Map);
    final viewOffset = _nonNegInt(view['byteOffset']);
    final accOffset = _nonNegInt(acc['byteOffset']);
    final offset = viewOffset + accOffset;
    final count = _nonNegInt(acc['count'], fallback: -1);
    if (count < 0 || count > maxAccessorElements) {
      throw const FormatException('Invalid glTF accessor count');
    }
    final byteStride = _nonNegInt(view['byteStride'], fallback: 12);
    if (byteStride < 12 || byteStride > 4096) {
      throw const FormatException('Invalid glTF Vec3 byteStride');
    }
    final requiredBytes = count == 0 ? 0 : (count - 1) * byteStride + 12;
    if (offset < 0 || offset + requiredBytes > buffer.length) {
      throw const FormatException('glTF Vec3 accessor exceeds binary buffer');
    }

    final data = ByteData.sublistView(buffer);
    final result = <Vector3>[];

    for (var i = 0; i < count; i++) {
      final base = offset + i * byteStride;
      final x = data.getFloat32(base, Endian.little);
      final y = data.getFloat32(base + 4, Endian.little);
      final z = data.getFloat32(base + 8, Endian.little);
      if (!x.isFinite || !y.isFinite || !z.isFinite) {
        throw const FormatException('Non-finite vertex in glTF buffer');
      }
      result.add(Vector3(x, y, z));
    }
    return result;
  }

  static List<int> _readIndexAccessor(
    dynamic accessor,
    List<dynamic> bufferViews,
    Uint8List buffer,
  ) {
    if (accessor is! Map) {
      throw const FormatException('glTF index accessor must be an object');
    }
    final acc = Map<String, dynamic>.from(accessor);
    final viewIdx = _optionalIndex(acc['bufferView'], bufferViews.length);
    if (viewIdx == null || bufferViews[viewIdx] is! Map) {
      throw const FormatException('Invalid glTF index bufferView');
    }
    final view = Map<String, dynamic>.from(bufferViews[viewIdx] as Map);
    final offset =
        _nonNegInt(view['byteOffset']) + _nonNegInt(acc['byteOffset']);
    final count = _nonNegInt(acc['count'], fallback: -1);
    if (count < 0 || count > maxAccessorElements) {
      throw const FormatException('Invalid glTF index count');
    }
    final componentType = _nonNegInt(acc['componentType'], fallback: -1);
    final elemBytes = switch (componentType) {
      5121 => 1, // UNSIGNED_BYTE
      5123 => 2, // UNSIGNED_SHORT
      5125 => 4, // UNSIGNED_INT
      _ => throw const FormatException('Unsupported glTF index componentType'),
    };
    if (offset < 0 || offset + count * elemBytes > buffer.length) {
      throw const FormatException('glTF index accessor exceeds binary buffer');
    }

    final data = ByteData.sublistView(buffer);
    final result = <int>[];

    for (var i = 0; i < count; i++) {
      if (componentType == 5123) {
        result.add(data.getUint16(offset + i * 2, Endian.little));
      } else if (componentType == 5125) {
        result.add(data.getUint32(offset + i * 4, Endian.little));
      } else {
        result.add(buffer[offset + i]);
      }
    }
    return result;
  }
}

/// Result of parsing a glTF file.
class GltfResult {
  final Node root;
  final List<MeshNode> meshes;
  final List<VRMaterial> materials;

  const GltfResult({
    required this.root,
    required this.meshes,
    required this.materials,
  });
}
