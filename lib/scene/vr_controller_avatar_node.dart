import 'dart:ui';

import 'package:vector_math/vector_math.dart';

import '../core/camera/camera_rig.dart';
import '../core/network/vr_controller_protocol.dart';
import '../spatial_ui/spatial_text.dart';
import 'material.dart';
import 'mesh.dart';
import 'node.dart';
import 'primitives/cube_geometry.dart';
import 'vr_controller_arm_model.dart';

/// Lightweight visual twin of a paired smartphone controller.
///
/// Position is deliberately head-relative in Lite mode; orientation comes from
/// the remote IMU. It communicates control layout and state without claiming
/// centimeter-accurate physical tracking.
class VrControllerAvatarNode extends Node {
  static const Color idleControlColor = Color(0xFF34506B);
  static const Color activeControlColor = Color(0xFF00E5FF);

  final VrControllerProfile profile;
  final CameraRig cameraRig;
  final double visualScale;
  final Vector3 anchorOffset;
  final VrControllerArmModel? armModel;

  final Map<String, _VrControllerControlVisual> _controls =
      <String, _VrControllerControlVisual>{};
  final Vector3 _forward = Vector3.zero();
  final Vector3 _right = Vector3.zero();
  final Vector3 _up = Vector3.zero();
  final Vector3 _anchoredPosition = Vector3.zero();

  late final MeshNode body;
  late final MeshNode screen;

  int _buttonsBitset = 0;
  double? rangeMeters;
  VrRangeSource? rangeSource;
  double? rangeConfidence;

  VrControllerAvatarNode({
    required this.profile,
    required this.cameraRig,
    this.visualScale = 2.0,
    Vector3? anchorOffset,
    this.armModel,
  }) : anchorOffset = anchorOffset?.clone() ?? Vector3(0.25, -0.24, 0.55),
       super(name: 'remote-controller-${profile.deviceId}') {
    if (!visualScale.isFinite || visualScale <= 0) {
      throw ArgumentError.value(
        visualScale,
        'visualScale',
        'Must be finite and positive.',
      );
    }
    _buildPhone();
  }

  int get buttonsBitset => _buttonsBitset;
  Iterable<String> get controlIds => _controls.keys;

  bool isControlActive(String id) => _controls[id]?.active ?? false;

  Node? controlNode(String id) => _controls[id]?.mesh;

  /// Applies the calibrated remote rotation without replacing quaternion storage.
  void updateOrientation(Quaternion orientation) {
    transform.setRotationFrom(orientation);
    onTransformChanged();
  }

  /// Bit N maps to control N in [VrControllerProfile.controls].
  void updateButtons(int bitset) {
    if (bitset < 0) {
      throw RangeError.value(bitset, 'bitset', 'Must not be negative.');
    }
    _buttonsBitset = bitset;
    for (var index = 0; index < profile.controls.length; index++) {
      _controls[profile.controls[index].id]?.setActive(
        bitset & (1 << index) != 0,
      );
    }
  }

  void updateRange({
    double? meters,
    VrRangeSource? source,
    double? confidence,
  }) {
    rangeMeters = meters;
    rangeSource = source;
    rangeConfidence = confidence;
  }

  @override
  void onUpdate(double dt) {
    final model = armModel;
    if (model != null) {
      model.update(
        cameraRig: cameraRig,
        controllerOrientation: transform.rotation,
        dt: dt,
        out: _anchoredPosition,
      );
      transform.setPositionFrom(_anchoredPosition);
      onTransformChanged();
      return;
    }

    cameraRig.headTransform.copyForwardTo(_forward);
    cameraRig.headTransform.copyRightTo(_right);
    cameraRig.headTransform.copyUpTo(_up);
    final head = cameraRig.position;
    _anchoredPosition.setValues(
      head.x +
          _right.x * anchorOffset.x +
          _up.x * anchorOffset.y +
          _forward.x * anchorOffset.z,
      head.y +
          _right.y * anchorOffset.x +
          _up.y * anchorOffset.y +
          _forward.y * anchorOffset.z,
      head.z +
          _right.z * anchorOffset.x +
          _up.z * anchorOffset.y +
          _forward.z * anchorOffset.z,
    );
    transform.setPositionFrom(_anchoredPosition);
    onTransformChanged();
  }

  void _buildPhone() {
    final width = profile.widthMeters * visualScale;
    final height = profile.heightMeters * visualScale;
    final depth = width * 0.11;

    body = MeshNode(
      name: 'controller-body',
      geometry: CubeGeometry(),
      material: VRMaterial(
        color: const Color(0xFF202833),
        metallic: 0.15,
        roughness: 0.7,
      ),
    );
    body.transform.scale = Vector3(width, height, depth);
    body.onTransformChanged();
    addChild(body);

    screen = MeshNode(
      name: 'controller-screen',
      geometry: CubeGeometry(),
      material: VRMaterial(
        color: const Color(0xFF07131D),
        emissive: const Color(0xFF062534),
      ),
    );
    screen.transform.position = Vector3(0, 0, depth * 0.56);
    screen.transform.scale = Vector3(width * 0.92, height * 0.93, depth * 0.08);
    screen.onTransformChanged();
    addChild(screen);

    for (var index = 0; index < profile.controls.length; index++) {
      final descriptor = profile.controls[index];
      final material = VRMaterial(
        color: idleControlColor,
        emissive: const Color(0xFF0C2438),
        roughness: 0.6,
      );
      final button = MeshNode(
        name: 'controller-control-${descriptor.id}',
        geometry: CubeGeometry(),
        material: material,
      );
      button.transform.position = Vector3(
        (descriptor.x - 0.5) * width,
        (0.5 - descriptor.y) * height,
        depth * 0.68,
      );
      button.transform.scale = Vector3(
        descriptor.width * width,
        descriptor.height * height,
        depth * 0.12,
      );
      button.onTransformChanged();
      addChild(button);

      final label = SpatialText(
        name: 'controller-label-${descriptor.id}',
        cameraRig: cameraRig,
        text: descriptor.label,
        fontSize: 0.03 * visualScale,
        color: const Color(0xFFFFFFFF),
        lockY: false,
      );
      label.transform.position = button.transform.position.clone()
        ..z += depth * 0.09;
      label.onTransformChanged();
      addChild(label);

      _controls[descriptor.id] = _VrControllerControlVisual(
        mesh: button,
        material: material,
        label: label,
      );
    }
  }
}

final class _VrControllerControlVisual {
  final MeshNode mesh;
  final VRMaterial material;
  final SpatialText label;
  bool active = false;

  _VrControllerControlVisual({
    required this.mesh,
    required this.material,
    required this.label,
  });

  void setActive(bool value) {
    if (active == value) return;
    active = value;
    material.color = value
        ? VrControllerAvatarNode.activeControlColor
        : VrControllerAvatarNode.idleControlColor;
    material.emissive = value
        ? VrControllerAvatarNode.activeControlColor
        : const Color(0xFF0C2438);
    label.color = value
        ? VrControllerAvatarNode.activeControlColor
        : const Color(0xFFFFFFFF);
  }
}
