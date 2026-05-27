<p align="center">
  <img src="https://firebasestorage.googleapis.com/v0/b/cyberneom-edd2d.appspot.com/o/AppStatics%2FVRlizate%20-%20VR%20Engine%20-%20Cover.png?alt=media&token=7f5dd0a6-25e3-4e84-af55-d094a4362aed" alt="VRlizate — VR Engine for Flutter" width="600"/>
</p>

# VRlizate

A complete 3D/VR engine written in **pure Dart** for Flutter.

No native plugins for rendering. No platform channels. No C++ bridge. One codebase — runs on iOS, Android, Web, macOS, Windows, and Linux.

```
5,334 lines of Dart  |  59 source files  |  2 dependencies  |  177 tests passing
```

## Why VRlizate Exists

VR needs to come back to the smartphone.

The industry spent years pushing standalone headsets — expensive, fragile, locked ecosystems. Meanwhile, billions of people already carry a GPU in their pocket. A phone + a $20 headset is a VR setup. VRlizate is built for that reality.

Flutter already runs on every platform. What it lacked was a 3D/VR engine that doesn't require native plugins, C++ bridges, or $500 hardware. VRlizate fills that gap: a pure Dart engine that renders stereoscopic VR on any Flutter target — including the phone you already own.

**The bet:** as `flutter_gpu` matures and mobile GPUs keep getting faster, the gap between phone-based VR and standalone headsets will shrink. VRlizate is positioned to ride that wave — today with Canvas rendering, tomorrow with GPU acceleration, always on the device you already have.

The entry cost drops from $500 (headset) to $20 (cardboard holder). The developer cost drops from learning Unity/C# to writing Dart. The deployment goes from sideloading APKs to `flutter build` for 6 platforms.

## Quick Start

```yaml
# pubspec.yaml
dependencies:
  vrlizate: ^1.0.0
```

```dart
import 'package:vrlizate/vrlizate.dart';

// Create engine
final engine = VREngine();
engine.cameraRig.position = Vector3(0, 1.6, 5);

// Add a lit cube
engine.scene.add(LitMeshNode(
  name: 'cube',
  geometry: CubeGeometry(size: 1),
  material: PBRMaterial(
    color: Color(0xFFDC2626),
    metallic: 0.9,
    roughness: 0.1,
  ),
));

// Add a point light
engine.scene.add(Light(
  type: LightType.point,
  color: Color(0xFFFFFFFF),
  intensity: 1.0,
)..transform.position = Vector3(2, 3, 2));

// Start the render loop
engine.start();
```

## Features

### Rendering
- Canvas-based 3D pipeline with depth sorting
- **Stereoscopic** (split-screen VR) and monoscopic modes
- Frustum culling with 6-plane extraction
- Opaque front-to-back, transparent back-to-front rendering

### Scene Graph
- Parent-child node hierarchy with transform inheritance
- **Quaternion-based rotation** (no gimbal lock)
- Cached world matrices with dirty flag optimization
- AABB bounds per node (auto-computed)
- Recursive traversal and name-based lookup

### Materials
- **VRMaterial** — color, emissive, opacity, metallic, roughness, wireframe
- **PBRMaterial** — Cook-Torrance BRDF approximation with texture support:
  - Color map (albedo)
  - Normal map with scale
  - Metallic/roughness map
  - Emission map with intensity
  - Ambient occlusion map
  - Environment map (IBL)
  - Alpha map

### Lighting
- Ambient, directional, point, and spot lights
- Distance attenuation (inverse-square) for point lights
- Spot cone angle calculation
- Per-face lighting in `LitMeshNode`

### Geometry
Procedural primitives with normals and UVs:
- `CubeGeometry` — 24 vertices, 36 indices
- `SphereGeometry` — configurable segments (up to 256+)
- `PlaneGeometry` — subdivisions support
- `CylinderGeometry` — configurable segments

### Physics
- Rigid body dynamics with velocity and angular velocity
- Gravity, force accumulation, impulse response
- AABB-based collision detection with impulse resolution
- Restitution, friction, linear/angular damping
- Ground plane collision
- Sleep state for optimization

### Animation
- **Skeleton** with `Skeleton.humanoid()` factory (16 bones)
- Skinning matrices for vertex deformation
- **AnimationClip** with keyframe tracks (Vector3, Quaternion)
- **AnimationMixer** with weighted multi-clip blending
- Easing curves: linear, easeIn, easeOut, easeInOut, elasticOut, bounceOut
- Auto-finish for non-looping clips

### Interaction
- **Raycaster** — AABB slab method with broad-phase culling
- **Grabbable** — grab/release with velocity tracking for throw physics
- **Pointable** — hover enter/exit, press/release with visual feedback
- **GazePointer** — eye-gaze based selection

### Locomotion
- **Fly** — free movement in all directions, snap turns (45 deg)
- **Walk** — ground-plane constrained, head or controller relative
- **Teleport** — point-and-teleport with max distance, cancel support

### Input
- **Head tracking** — gyroscope with auto-calibration and sensitivity control
- **Hand tracking** — 26 joints (OpenXR standard), gesture detection:
  - Pinch (thumb-index distance)
  - Fist (all fingers curled)
  - Pointing (index extended)
  - Pointing ray (palm through index tip)
- **Controllers** — thumbstick, grip, trigger, position, forward direction

### Spatial UI
- **Billboard** — always faces camera
- **Panel** — floating 3D rectangle with background, border, custom content
- **SpatialButton** — interactive button in 3D space
- **SpatialText** — text rendering in world space

### Effects
- **Fog** — exponential with color, density, near/far
- **Bloom** — Gaussian blur, screen blend
- **SSAO** — screen-space ambient occlusion
- **Vignette** — edge darkening
- **Lens Distortion** — barrel distortion with chromatic aberration (Google Cardboard v2 preset)

### Camera
- Stereoscopic rig with configurable **IPD** (0.064m default)
- Off-axis projection for proper convergence
- Configurable FOV, near/far clip planes
- Left/right/mono view-projection matrices

### Asset Loading
- **glTF 2.0** parser (JSON and binary GLB)
- Extracts meshes, materials (PBR), node hierarchy, transforms
- Handles rotation as quaternion, scale, translation

### Debug
- FPS counter with frame time overlay
- Render statistics (culled/rendered nodes)
- Grid floor for spatial reference

## Architecture

```
lib/
├── core/
│   ├── camera/        CameraRig (stereoscopic, IPD, off-axis projection)
│   ├── engine/        VREngine (60fps game loop via Timer.periodic)
│   ├── input/         HeadTracker, GazePointer, ControllerState, HandState
│   ├── math/          Transform3D (quaternion), Aabb
│   ├── projection/    StereoscopicProjection (side-by-side, barrel)
│   └── rendering/     RenderPass, VRRenderer (stereo/mono painters), ShaderProgram
├── scene/
│   ├── node.dart      Scene graph — hierarchy, transforms, traversal
│   ├── mesh.dart      MeshNode, LitMeshNode (per-face lighting)
│   ├── geometry.dart  Vertices, normals, UVs, indices, auto AABB
│   ├── material.dart  VRMaterial (Phong)
│   ├── pbr_material.dart  PBRMaterial (Cook-Torrance BRDF, texture maps)
│   ├── light.dart     Directional, Point, Spot lights
│   ├── texture.dart   Texture loading + procedural generation
│   └── primitives/    Cube, Sphere, Plane, Cylinder
├── animation/         AnimationClip, AnimationMixer, Keyframe, Skeleton, SkinDeformer
├── effects/           Bloom, Fog, SSAO, Vignette, LensDistortion, DistortionMesh
├── interaction/       Grabbable, Pointable, Raycaster
│   └── locomotion/    Fly, Walk, Teleport
├── loaders/           GltfParser (JSON + GLB binary)
├── physics/           RigidBody, PhysicsWorld (gravity, collision, impulse)
├── spatial_ui/        Billboard, Panel, SpatialButton, SpatialText
├── debug/             DebugOverlay, GridFloor
└── components/        VRScene, VRElement (StatefulWidget wrappers)
```

## Examples

### VR Gallery
A room with 3D objects you can grab, inspect, and teleport to.

```dart
// exhibits with grabbable PBR objects
engine.scene.add(LitMeshNode(
  name: 'Ruby Cube',
  geometry: CubeGeometry(size: 0.4),
  material: PBRMaterial(color: Color(0xFFDC2626), metallic: 0.9, roughness: 0.1),
));

// Teleport locomotion
final teleport = TeleportLocomotion(cameraRig: engine.cameraRig, scene: engine.scene);
```

### Open World
Large outdoor scene with day/night cycle, weather system, and NPC mobs.

### Hand Tracking
Real-time hand gesture recognition — pinch, fist, point.

### Spatial UI
Floating 3D panels, buttons, and text in world space.

### Treasure Hunt
Spatial puzzle game with raycasting interaction.

All examples live in `examples/`.

## Benchmarks

177 tests. 100% pass rate. All benchmarks run on Apple Silicon under `flutter test`.

### Performance

| Subsystem | Operation | Scale | Time |
|---|---|---|---|
| **Scene Graph** | Traverse | 10,000 nodes | < 200ms |
| **Scene Graph** | Traverse mixed tree | 19,531 nodes | < 500ms |
| **Scene Graph** | Deep hierarchy | 100 levels | instant |
| **Frustum Culling** | Cull AABBs | 10,000 boxes | < 50ms |
| **Raycasting** | Cast rays | 1,000 rays x 500 nodes | < 500ms |
| **Physics** | Rigid body sim | 50 bodies x 500 steps | < 5s |
| **Geometry** | Sphere (128 seg) | 16,641 verts | < 100ms |
| **Geometry** | Sphere (256 seg) | 66,049 verts | < 500ms |
| **Geometry** | Batch (10 x 64 seg) | 42,250 verts | < 200ms |
| **Math** | Matrix from quaternion | 10,000 transforms | < 50ms |
| **Math** | AABB expansion | 100,000 points | < 100ms |
| **Math** | AABB intersection | 10,000 pairs | < 20ms |
| **Material** | toPaint() | 10,000 calls | < 50ms |
| **glTF** | Parse 100 nodes | JSON + transforms | < 50ms |
| **Render Pipeline** | `renderMono` | 1,000 Opaque + 200 Transparent | < 50ms |
| **Render Pipeline** | Frustum Culling | 900 out-of-view objects | < 15ms |

### Correctness

| Subsystem | Validated |
|---|---|
| **Scene Graph** | Transform propagation through 3-level hierarchy: exact |
| **Physics** | Energy conservation (bouncing): monotonic decay |
| **Physics** | Impulse proportional to mass: exact |
| **Animation** | Keyframe interpolation at t=0, 0.5, 1.0: exact |
| **Animation** | Easing functions bounded [0,1] and monotonic |
| **Animation** | Humanoid skeleton: 16 bones, all skinning matrices valid |
| **Geometry** | All indices within vertex range (all primitives) |
| **Geometry** | AABB contains all vertices (sphere, cube) |
| **Geometry** | Sphere normals consistent direction (>95%) |
| **Frustum** | Point inside/outside/behind camera: correct |
| **Frustum** | AABB inside/outside/intersecting: correct |
| **Raycasting** | Hits sorted by distance (nearest first) |
| **Raycasting** | Invisible nodes skipped |
| **Raycasting** | maxDistance enforced |
| **glTF** | PBR material values parsed exactly |
| **glTF** | Invalid GLB rejected with FormatException |
| **Material** | Opacity affects paint alpha |
| **Material** | Wireframe produces stroke paint |
| **Render Pipeline** | Frustum culling: exact node exclusion |
| **Render Pipeline** | Transparent sorting: strict back-to-front |
| **Render Pipeline** | Stereo rendering: symmetry & viewport clipping |

Run all benchmarks yourself:
```bash
flutter test                        # all 177 tests
flutter test test/benchmark_*.dart  # benchmarks only
```

Full benchmark details in [BENCHMARKS.md](BENCHMARKS.md).

## Comparison

| | VRlizate | three_d | flame_3d | Unity (platform view) |
|---|:---:|:---:|:---:|:---:|
| Pure Dart | Yes | Yes | Partial | No |
| VR stereo | Built-in | - | - | External |
| Physics | Built-in | - | - | Built-in |
| Skeletal animation | Built-in | - | Basic | Built-in |
| Interaction (grab, gaze) | Built-in | - | - | External |
| glTF loader | Built-in | - | - | Built-in |
| Spatial UI | Built-in | - | - | External |
| Dependencies | **2** | varies | many | N/A |
| Cross-platform | **6** | limited | limited | PlatformView |
| Test suite | **177** | minimal | minimal | N/A |

## Dependencies

Two. That's it.

- [`vector_math`](https://pub.dev/packages/vector_math) — vectors, matrices, quaternions
- [`sensors_plus`](https://pub.dev/packages/sensors_plus) — gyroscope for head tracking

## Roadmap

| Feature | Status |
|---|---|
| GPU rendering via `flutter_gpu` | Interface ready, awaiting API stability |
| Image-based textures | Data structures ready, Canvas UV mapping pending |
| Shadow mapping | Module exists, implementation in progress |
| WebXR session bridge | Module exists, browser integration pending |
| Spatial audio | Planned |

## Platforms

| Platform | Rendering | Head Tracking | Status |
|---|---|---|---|
| iOS | Canvas | Gyroscope | Tested |
| Android | Canvas | Gyroscope | Tested |
| Web (Chrome) | Canvas | Touch fallback | Tested |
| macOS | Canvas | Touch fallback | Primary dev |
| Windows | Canvas | Touch fallback | Supported |
| Linux | Canvas | Touch fallback | Supported |

## License

Apache License 2.0 — [Open Neom](https://github.com/Open-Neom)
