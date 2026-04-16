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
  /// Parses a glTF JSON string and returns the root node.
  static GltfResult parseJson(String jsonString, {Uint8List? binaryBuffer}) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return _parse(json, binaryBuffer);
  }

  /// Parses a GLB binary buffer.
  static GltfResult parseGlb(Uint8List glbData) {
    // GLB header: magic(4) + version(4) + length(4) = 12 bytes
    final magic = ByteData.sublistView(
      glbData,
      0,
      4,
    ).getUint32(0, Endian.little);
    if (magic != 0x46546C67) {
      throw const FormatException('Invalid GLB magic number');
    }

    // Chunk 0: JSON
    final jsonLength = ByteData.sublistView(
      glbData,
      12,
      16,
    ).getUint32(0, Endian.little);
    final jsonString = utf8.decode(glbData.sublist(20, 20 + jsonLength));

    // Chunk 1: Binary (optional)
    Uint8List? binBuffer;
    if (glbData.length > 20 + jsonLength + 8) {
      final binOffset = 20 + jsonLength;
      final binLength = ByteData.sublistView(
        glbData,
        binOffset,
        binOffset + 4,
      ).getUint32(0, Endian.little);
      binBuffer = glbData.sublist(binOffset + 8, binOffset + 8 + binLength);
    }

    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return _parse(json, binBuffer);
  }

  static GltfResult _parse(Map<String, dynamic> gltf, Uint8List? buffer) {
    final meshes = <MeshNode>[];

    // Parse materials
    final materials = <VRMaterial>[];
    final matList = gltf['materials'] as List<dynamic>? ?? [];
    for (final mat in matList) {
      final m = mat as Map<String, dynamic>;
      final pbr = m['pbrMetallicRoughness'] as Map<String, dynamic>? ?? {};
      final baseColor = pbr['baseColorFactor'] as List<dynamic>?;

      materials.add(
        VRMaterial(
          color: baseColor != null
              ? Color.fromARGB(
                  ((baseColor[3] as num) * 255).toInt(),
                  ((baseColor[0] as num) * 255).toInt(),
                  ((baseColor[1] as num) * 255).toInt(),
                  ((baseColor[2] as num) * 255).toInt(),
                )
              : const Color(0xFFCCCCCC),
          metallic: (pbr['metallicFactor'] as num?)?.toDouble() ?? 0,
          roughness: (pbr['roughnessFactor'] as num?)?.toDouble() ?? 1,
          doubleSided: m['doubleSided'] as bool? ?? false,
        ),
      );
    }

    // Parse meshes
    final meshList = gltf['meshes'] as List<dynamic>? ?? [];
    final accessors = gltf['accessors'] as List<dynamic>? ?? [];
    final bufferViews = gltf['bufferViews'] as List<dynamic>? ?? [];

    for (final mesh in meshList) {
      final primitives =
          (mesh as Map<String, dynamic>)['primitives'] as List<dynamic>? ?? [];

      for (final prim in primitives) {
        final p = prim as Map<String, dynamic>;
        final attrs = p['attributes'] as Map<String, dynamic>? ?? {};

        // Extract vertex positions
        final posAccessor = attrs['POSITION'] as int?;
        final vertices = posAccessor != null && buffer != null
            ? _readVec3Accessor(accessors[posAccessor], bufferViews, buffer)
            : <Vector3>[Vector3.zero()];

        // Extract normals
        final normAccessor = attrs['NORMAL'] as int?;
        final normals = normAccessor != null && buffer != null
            ? _readVec3Accessor(accessors[normAccessor], bufferViews, buffer)
            : null;

        // Extract indices
        final idxAccessor = p['indices'] as int?;
        final indices = idxAccessor != null && buffer != null
            ? _readIndexAccessor(accessors[idxAccessor], bufferViews, buffer)
            : List.generate(vertices.length, (i) => i);

        // Material
        final matIdx = p['material'] as int?;
        final material = matIdx != null && matIdx < materials.length
            ? materials[matIdx]
            : VRMaterial();

        final geometry = Geometry(
          vertices: vertices,
          normals: normals,
          indices: indices,
        );

        final meshNode = MeshNode(
          name: (mesh)['name'] as String? ?? 'mesh',
          geometry: geometry,
          material: material,
        );
        meshes.add(meshNode);
      }
    }

    // Parse node hierarchy
    final nodeList = gltf['nodes'] as List<dynamic>? ?? [];
    final parsedNodes = <Node>[];

    for (final n in nodeList) {
      final nd = n as Map<String, dynamic>;
      final node = Node(name: nd['name'] as String? ?? '');

      // Transform
      final translation = nd['translation'] as List<dynamic>?;
      if (translation != null) {
        node.transform.position = Vector3(
          (translation[0] as num).toDouble(),
          (translation[1] as num).toDouble(),
          (translation[2] as num).toDouble(),
        );
      }

      final rotation = nd['rotation'] as List<dynamic>?;
      if (rotation != null) {
        node.transform.rotation = Quaternion(
          (rotation[0] as num).toDouble(),
          (rotation[1] as num).toDouble(),
          (rotation[2] as num).toDouble(),
          (rotation[3] as num).toDouble(),
        );
      }

      final scale = nd['scale'] as List<dynamic>?;
      if (scale != null) {
        node.transform.scale = Vector3(
          (scale[0] as num).toDouble(),
          (scale[1] as num).toDouble(),
          (scale[2] as num).toDouble(),
        );
      }

      // Attach mesh if referenced
      final meshIdx = nd['mesh'] as int?;
      if (meshIdx != null && meshIdx < meshes.length) {
        node.addChild(meshes[meshIdx]);
      }

      parsedNodes.add(node);
    }

    // Build hierarchy
    for (var i = 0; i < nodeList.length; i++) {
      final children =
          (nodeList[i] as Map<String, dynamic>)['children'] as List<dynamic>?;
      if (children != null) {
        for (final childIdx in children) {
          if (childIdx is int && childIdx < parsedNodes.length) {
            parsedNodes[i].addChild(parsedNodes[childIdx]);
          }
        }
      }
    }

    // Root node
    final root = Node(name: 'gltf_root');
    final sceneIdx = gltf['scene'] as int? ?? 0;
    final scenes = gltf['scenes'] as List<dynamic>? ?? [];
    if (sceneIdx < scenes.length) {
      final sceneNodes =
          (scenes[sceneIdx] as Map<String, dynamic>)['nodes']
              as List<dynamic>? ??
          [];
      for (final nodeIdx in sceneNodes) {
        if (nodeIdx is int && nodeIdx < parsedNodes.length) {
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

  static List<Vector3> _readVec3Accessor(
    dynamic accessor,
    List<dynamic> bufferViews,
    Uint8List buffer,
  ) {
    final acc = accessor as Map<String, dynamic>;
    final viewIdx = acc['bufferView'] as int;
    final view = bufferViews[viewIdx] as Map<String, dynamic>;
    final offset =
        (view['byteOffset'] as int? ?? 0) + (acc['byteOffset'] as int? ?? 0);
    final count = acc['count'] as int;

    final data = ByteData.sublistView(buffer);
    final result = <Vector3>[];

    for (var i = 0; i < count; i++) {
      final base = offset + i * 12; // 3 floats × 4 bytes
      result.add(
        Vector3(
          data.getFloat32(base, Endian.little),
          data.getFloat32(base + 4, Endian.little),
          data.getFloat32(base + 8, Endian.little),
        ),
      );
    }
    return result;
  }

  static List<int> _readIndexAccessor(
    dynamic accessor,
    List<dynamic> bufferViews,
    Uint8List buffer,
  ) {
    final acc = accessor as Map<String, dynamic>;
    final viewIdx = acc['bufferView'] as int;
    final view = bufferViews[viewIdx] as Map<String, dynamic>;
    final offset =
        (view['byteOffset'] as int? ?? 0) + (acc['byteOffset'] as int? ?? 0);
    final count = acc['count'] as int;
    final componentType = acc['componentType'] as int;

    final data = ByteData.sublistView(buffer);
    final result = <int>[];

    for (var i = 0; i < count; i++) {
      if (componentType == 5123) {
        // UNSIGNED_SHORT
        result.add(data.getUint16(offset + i * 2, Endian.little));
      } else if (componentType == 5125) {
        // UNSIGNED_INT
        result.add(data.getUint32(offset + i * 4, Endian.little));
      } else {
        // UNSIGNED_BYTE
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
