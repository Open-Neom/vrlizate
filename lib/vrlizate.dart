/// vrlizate — VR 3D engine for Flutter.
///
/// Complete VR framework: scene graph, PBR materials, mesh rendering,
/// lighting with shadows, stereoscopic projection, head/hand tracking,
/// raycasting, spatial UI, locomotion, physics, animation with skeletal
/// deformation, glTF loading, effects, and WebXR session management.
///
/// ```dart
/// import 'package:vrlizate/vrlizate.dart';
///
/// final engine = VREngine();
/// engine.scene.add(LitMeshNode(
///   geometry: CubeGeometry(),
///   material: PBRMaterial(color: Color(0xFF2E90FA), metallic: 0.8),
/// ));
/// engine.scene.add(Light.directional());
/// engine.enableHeadTracking();
/// engine.start();
///
/// CustomPaint(painter: engine.stereoPainter)
/// ```
library;

// ============ Core — Math ============
export 'core/math/aabb.dart';
export 'core/math/transform3d.dart';

// ============ Core — Camera ============
export 'core/camera/camera_rig.dart';
export 'core/camera/vr_camera.dart';

// ============ Core — Input ============
export 'core/input/controller_state.dart';
export 'core/input/gaze_pointer.dart';
export 'core/input/hand_state.dart';
export 'core/input/head_tracker.dart';

// ============ Core — Projection ============
export 'core/projection/stereoscopic_projection.dart';

// ============ Core — Rendering ============
export 'core/rendering/gpu_renderer.dart';
export 'core/rendering/render_pass.dart';
export 'core/rendering/shader_program.dart';
export 'core/rendering/vr_renderer.dart';

// ============ Core — Engine ============
export 'core/engine/vr_engine.dart';

// ============ Scene Graph ============
export 'scene/geometry.dart';
export 'scene/light.dart';
export 'scene/material.dart';
export 'scene/mesh.dart';
export 'scene/node.dart';
export 'scene/pbr_material.dart';
export 'scene/scene.dart';
export 'scene/shadow.dart';
export 'scene/texture.dart';

// ============ Primitives ============
export 'scene/primitives/cube_geometry.dart';
export 'scene/primitives/cylinder_geometry.dart';
export 'scene/primitives/plane_geometry.dart';
export 'scene/primitives/sphere_geometry.dart';

// ============ Animation ============
export 'animation/animation_clip.dart';
export 'animation/animation_mixer.dart';
export 'animation/keyframe.dart';
export 'animation/skeleton.dart';
export 'animation/skin_deformer.dart';

// ============ Interaction ============
export 'interaction/grabbable.dart';
export 'interaction/pointable.dart';
export 'interaction/raycast.dart';

// ============ Locomotion ============
export 'interaction/locomotion/fly.dart';
export 'interaction/locomotion/teleport.dart';
export 'interaction/locomotion/walk.dart';

// ============ Spatial UI ============
export 'spatial_ui/billboard.dart';
export 'spatial_ui/panel.dart';
export 'spatial_ui/spatial_button.dart';
export 'spatial_ui/spatial_text.dart';

// ============ Physics ============
export 'physics/rigid_body.dart';

// ============ Loaders ============
export 'loaders/gltf_parser.dart';

// ============ Effects ============
export 'effects/bloom.dart';
export 'effects/device_params.dart';
export 'effects/distortion_mesh.dart';
export 'effects/fog.dart';
export 'effects/lens_distortion.dart';
export 'effects/ssao.dart';
export 'effects/vignette.dart';

// ============ XR ============
export 'xr/webxr_session.dart';

// ============ Debug ============
export 'debug/debug_overlay.dart';
export 'debug/grid_floor.dart';

// ============ Legacy Components ============
export 'components/vr_element.dart';
export 'components/vr_scene.dart';

// ============ Utils ============
export 'utils/frustum.dart';
export 'utils/vr_math.dart';
