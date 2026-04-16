# Changelog

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
