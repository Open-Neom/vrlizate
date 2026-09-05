import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math.dart';

import '../interaction/pointable.dart';
import '../scene/material.dart';
import '../scene/mesh.dart';
import '../scene/node.dart';
import '../scene/primitives/cube_geometry.dart';

/// A gaze/tap-enabled 3D arrow that points toward the upper-left.
///
/// It is intended as a consistent spatial "back" affordance. The arrow is
/// built from real meshes (rather than a text glyph), so it keeps its depth
/// and silhouette in stereoscopic rendering.
class SpatialNavigationArrow extends Node {
  final Color idleColor;
  final Color hoverColor;
  final Color pressColor;
  final List<VRMaterial> _materials = [];

  SpatialNavigationArrow({
    super.name = 'spatial_back_arrow',
    super.transform,
    this.idleColor = const Color(0xFF38BDF8),
    this.hoverColor = const Color(0xFF67E8F9),
    this.pressColor = const Color(0xFFFFFFFF),
    void Function(Node node)? onPress,
  }) {
    _addBar(
      name: '${name}_shaft',
      position: Vector3(0.04, -0.04, 0),
      scale: Vector3(0.64, 0.10, 0.10),
      rotationZ: -math.pi / 4,
    );
    _addBar(
      name: '${name}_head_horizontal',
      position: Vector3(-0.16, 0.24, 0),
      scale: Vector3(0.30, 0.10, 0.10),
    );
    _addBar(
      name: '${name}_head_vertical',
      position: Vector3(-0.28, 0.12, 0),
      scale: Vector3(0.10, 0.30, 0.10),
    );

    pointable = Pointable(
      node: this,
      onHoverEnter: (_) => _setColor(hoverColor),
      onHoverExit: (_) => _setColor(idleColor),
      onPress: (node, _) {
        _setColor(pressColor);
        onPress?.call(node);
      },
      onRelease: (_) => _setColor(hoverColor),
    );
  }

  void _addBar({
    required String name,
    required Vector3 position,
    required Vector3 scale,
    double rotationZ = 0,
  }) {
    final material = VRMaterial.glow(color: idleColor);
    material.doubleSided = true;
    _materials.add(material);

    final bar = MeshNode(
      name: name,
      geometry: CubeGeometry(),
      material: material,
    );
    bar.transform.position = position;
    bar.transform.scale = scale;
    if (rotationZ != 0) {
      bar.transform.rotation = Quaternion.axisAngle(
        Vector3(0, 0, 1),
        rotationZ,
      );
    }
    bar.onTransformChanged();
    addChild(bar);
  }

  void _setColor(Color color) {
    for (final material in _materials) {
      material.color = color;
      material.emissive = color;
    }
  }
}
