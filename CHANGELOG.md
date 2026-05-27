# Changelog

## 1.2.0 — 2026-05

### Changed
- Refactored `VRParticle` and `VRRing` classes to make `color` a non-final mutable field to enable real-time dynamic modulation for audio-reactive and visual animation effects.

## 1.1.0 — 2026-05

### Added
- **IMU Complementary Sensor Fusion**: Stabilized landscape VR tracking by combining high-frequency gyroscope integration with low-frequency absolute gravity accelerometer vectors ($\alpha = 0.98$) to eliminate head tracking drift.
- **Google Cardboard Neck Model**: Implemented realistic head-to-neck physical pivot rotations for camera projection, delivering comfortable stereoscopic parallax and dramatically reducing VR motion sickness.
- **Turbo-Canvas Render Engine Optimization**: Shifted flat-shaded face rendering to use Flutter's ultra-high-performance `canvas.drawVertices` with `ui.Vertices` batched triangulation, replacing slow iterative path drawing with direct GPU-friendly vertex buffers.
- **Injectable Sensor Streams**: Refactored `HeadTracker` constructor to accept optional mock streams (`gyroscopeStreamOverride`, `accelerometerStreamOverride`), enabling complete deterministic offline simulation and testing of IMU inputs.
- **Expanded Test Suite**: Added comprehensive unit tests validating complementary filter math stability, noisy drift calibration offsets, symmetric eye offsets, and physical neck model boundaries (170 tests passing at 100%).
- **OSI Apache-2.0 License compliance**: Replaced generic license templates with the official Apache 2.0 license file to recover full pub.dev score points under file conventions.

### Fixed
- **Static Analysis warnings**: Resolved all 14 lint warnings and info items (e.g. deprecated `.red` usage, unused imports/variables, non-const declarations, and package dependency rules) achieving 0 issues across the engine and example.
- **Dependency boundaries updated**: Raised `sensors_plus` constraint to `^7.0.0` and optimized `vector_math` to `^2.2.0` to support modern platforms while avoiding SDK version solver pins.

### Future Roadmap & Surrounding Integrations
- **Unified Locomotion Driver**: Incorporate touch joysticks from neighboring 3D engines (e.g. `openworlddart`) to combine with the built-in accelerometer physical step-locomotion peak detector.
- **OpenXR Joint Mapping Alignment**: Standardize the 26-joint tracking framework inside `HandState` to match Khronos OpenXR specifications for future FFI driver compatibility.
- **Cardboard QR Profile Loader**: Implement pure-Dart base64 protocol buffer profile decoders to parse QR codes for custom lens radial distortion models dynamically.
- **Aesthetic "WOW" Factor Expansion**: Build togglable **PBR Physics Playgrounds** (interacting with metallic reflectives and grabbing objects with dynamic impulse responses) and **Deep Space Flight Simulators** directly within the interactive sample app.

## 1.0.0 — 2026-04


### Added
- VR Celestial Compass example: wireframe globe, cardinal markers, SpatialText labels, zone detection, step locomotion
- `analysis_options.yaml` with Flutter lint rules
- `example/` app scaffold (Android/iOS/macOS/Web/Linux/Windows) with pub.dev example.dart
- `issue_tracker` and `platforms` fields in pubspec.yaml
- Cover image in README and pub.dev screenshots
- Zone detection system based on Meta VR research (30°/55°/135° thresholds)
- Step detection via accelerometer peak detection

### Fixed
- **Head tracking**: correct landscape gyroscope axis mapping (X→yaw, Y→pitch)
- **Head tracking**: inverted horizontal direction fixed
- **Head tracking**: vertical sensitivity amplified ×1.8 for comfortable up/down range
- **LitMeshNode**: `lights` list now mutable (was `const []`, caused runtime crash)
- Deprecated `Color.red/green/blue/alpha` API replaced with `Color.r/g/b/a`
- Removed unnecessary `dart:typed_data` import in texture.dart
- Fixed dangling library doc comment in webxr_session.dart
- All 36 analyzer warnings and hints resolved (0 issues)
- Dart format applied to all 59 source files

### Changed
- Version 1.0.0 — first stable release
- README Quick Start uses pub.dev dependency

## 0.1.0 — 2026-04

### Added
- Initial VR engine: 59 Dart source files
- Scene graph with hierarchical nodes and transforms
- Mesh rendering with Phong + PBR materials
- Stereoscopic side-by-side projection
- Head tracking via gyroscope (sensors_plus)
- Interaction: gaze pointer, raycast, grabbable, pointable
- Locomotion: fly, teleport, walk
- Animation: clips, mixer, keyframes, skeleton, skin deformer
- Effects: bloom, fog, SSAO, vignette, lens distortion
- Primitive geometries: cube, sphere, plane, cylinder
- Basic glTF 2.0 parser
- Spatial UI: billboard, panel, button, text
- WebXR session bridge
- Debug overlay and grid floor
- Physics: rigid body, AABB collision, gravity
- 163 tests with benchmarks
- 5 demo examples: VR Gallery, Treasure Hunt, Open World, Spatial UI, Hand Tracking
