import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart' show TextPainter, TextSpan, TextStyle, FontWeight;
import 'package:vector_math/vector_math.dart' hide Colors;
import 'package:vrlizate/vrlizate.dart';

abstract class VRDemo {
  final VREngine engine;
  final List<Node> nodes = [];

  VRDemo(this.engine);

  void init();
  void update(double dt);
  void handleTap() {
    engine.handleTap();
  }

  void dispose() {
    for (final node in nodes) {
      node.removeFromParent();
    }
    nodes.clear();
  }
}

// ============================================================================
// 1. Physics Playground Demo
// ============================================================================
class PhysicsPlaygroundDemo extends VRDemo {
  late final PhysicsWorld physicsWorld;
  Node? grabbedNode;
  double grabbedDist = 0.0;
  final List<RigidBody> bodies = [];

  PhysicsPlaygroundDemo(super.engine);

  @override
  void init() {
    physicsWorld = PhysicsWorld(groundY: -1.6);

    // Dynamic ground plane mesh for visuals
    final ground = LitMeshNode(
      name: 'phys_ground',
      geometry: PlaneGeometry(width: 40, height: 40),
      material: VRMaterial(color: const Color(0xFF1E293B), metallic: 0.2, roughness: 0.8),
    )..transform.position = Vector3(0, -1.6, 0)
     ..onTransformChanged();
    engine.scene.add(ground);
    nodes.add(ground);

    // Stacking Pyramid of Cubes
    final boxGeometry = CubeGeometry(size: 0.6);
    final boxColors = [
      const Color(0xFFEF4444),
      const Color(0xFFF97316),
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
      const Color(0xFF3B82F6),
      const Color(0xFF8B5CF6),
    ];

    var colorIndex = 0;
    // Row 1 (bottom, 3 boxes)
    for (var x = -1; x <= 1; x++) {
      _createPhysicsBox(Vector3(x * 0.8, -1.3, -4.0), boxGeometry, boxColors[colorIndex++ % boxColors.length]);
    }
    // Row 2 (middle, 2 boxes)
    for (var x = -0.5; x <= 0.5; x += 1.0) {
      _createPhysicsBox(Vector3(x * 0.8, -0.7, -4.0), boxGeometry, boxColors[colorIndex++ % boxColors.length]);
    }
    // Row 3 (top, 1 box)
    _createPhysicsBox(Vector3(0.0, -0.1, -4.0), boxGeometry, boxColors[colorIndex++ % boxColors.length]);

    // Bouncy Spheres
    final sphereGeometry = SphereGeometry(radius: 0.35, segments: 12);
    for (var i = 0; i < 3; i++) {
      _createPhysicsSphere(Vector3(-1.8 + i * 1.8, 1.2, -5.0), sphereGeometry, const Color(0xFF06B6D4));
    }
  }

  void _createPhysicsBox(Vector3 position, Geometry geom, Color color) {
    final node = LitMeshNode(
      name: 'phys_box_${bodies.length}',
      geometry: geom,
      material: VRMaterial(color: color, metallic: 0.5, roughness: 0.5),
    )..transform.position = position
     ..onTransformChanged();

    node.pointable = Pointable(
      node: node,
      onHoverEnter: (_) => node.material.emissive = color.withValues(alpha: 0.3),
      onHoverExit: (_) => node.material.emissive = const Color(0xFF000000),
      onPress: (n, hit) {
        if (grabbedNode == null) {
          grabbedNode = n;
          grabbedDist = hit.distance;
          final body = physicsWorld.bodies.firstWhere((b) => b.node == n);
          body.useGravity = false;
          body.velocity = Vector3.zero();
          body.angularVelocity = Vector3.zero();
          body.isSleeping = false;
        }
      },
    );

    engine.scene.add(node);
    nodes.add(node);

    final body = RigidBody(node: node, mass: 2.0, restitution: 0.2, friction: 0.6);
    physicsWorld.addBody(body);
    bodies.add(body);
  }

  void _createPhysicsSphere(Vector3 position, Geometry geom, Color color) {
    final node = LitMeshNode(
      name: 'phys_sphere_${bodies.length}',
      geometry: geom,
      material: VRMaterial(color: color, metallic: 0.8, roughness: 0.2),
    )..transform.position = position
     ..onTransformChanged();

    node.pointable = Pointable(
      node: node,
      onHoverEnter: (_) => node.material.emissive = color.withValues(alpha: 0.4),
      onHoverExit: (_) => node.material.emissive = const Color(0xFF000000),
      onPress: (n, hit) {
        if (grabbedNode == null) {
          grabbedNode = n;
          grabbedDist = hit.distance;
          final body = physicsWorld.bodies.firstWhere((b) => b.node == n);
          body.useGravity = false;
          body.velocity = Vector3.zero();
          body.angularVelocity = Vector3.zero();
          body.isSleeping = false;
        }
      },
    );

    engine.scene.add(node);
    nodes.add(node);

    final body = RigidBody(node: node, mass: 1.5, restitution: 0.8, friction: 0.3);
    physicsWorld.addBody(body);
    bodies.add(body);
  }

  @override
  void update(double dt) {
    if (grabbedNode != null) {
      final targetPos = engine.cameraRig.position + engine.cameraRig.headTransform.forward * grabbedDist;
      grabbedNode!.transform.position = targetPos;
      grabbedNode!.onTransformChanged();
    }

    // Limit physics steps to avoid huge jumps on frame drops
    physicsWorld.update(dt.clamp(0.005, 0.033));
  }

  @override
  void handleTap() {
    if (grabbedNode != null) {
      final body = physicsWorld.bodies.firstWhere((b) => b.node == grabbedNode);
      body.useGravity = true;
      body.isSleeping = false;
      // Launch forward in camera gaze direction
      body.applyImpulse(engine.cameraRig.headTransform.forward * 18.0);
      grabbedNode = null;
    } else {
      engine.handleTap();
    }
  }

  @override
  void dispose() {
    super.dispose();
    bodies.clear();
  }
}

// ============================================================================
// 2. Deep Space Flight Simulator
// ============================================================================
class StarfieldNode extends Node {
  final CameraRig cameraRig;
  final List<Vector3> starDirections = [];
  final List<double> starSizes = [];

  StarfieldNode({required this.cameraRig}) : super(name: 'starfield') {
    final random = Random(1337);
    for (var i = 0; i < 200; i++) {
      final theta = random.nextDouble() * 2.0 * pi;
      final phi = acos(2.0 * random.nextDouble() - 1.0);
      final dir = Vector3(
        sin(phi) * cos(theta),
        sin(phi) * sin(theta),
        cos(phi),
      )..normalize();
      starDirections.add(dir);
      starSizes.add(0.4 + random.nextDouble() * 1.2);
    }
  }

  @override
  void onRender(Canvas canvas, Matrix4 viewProjection) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < starDirections.length; i++) {
      final dir = starDirections[i];
      final starPos = cameraRig.position + dir * 95.0; // Draw infinitely far
      
      final clip = viewProjection * Vector4(starPos.x, starPos.y, starPos.z, 1.0);
      if (clip.w <= 0.001) continue;

      final ndcX = clip.x / clip.w;
      final ndcY = clip.y / clip.w;

      // Draw dot scaled to NDC coordinates (400 represents half-width scale of viewport)
      canvas.drawCircle(Offset(ndcX, ndcY), starSizes[i] / 400.0, paint);
    }
  }
}

class CockpitHudNode extends Node {
  final CameraRig cameraRig;
  final List<LitMeshNode> planets;

  CockpitHudNode({required this.cameraRig, required this.planets}) : super(name: 'cockpit_hud');

  @override
  void onRender(Canvas canvas, Matrix4 viewProjection) {
    // Project cockpit lines in front of camera
    final paint = Paint()
      ..color = const Color(0x6600FFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / 400.0;

    // Draw a neat cockpit frame / crosshair in central NDC [-0.15, 0.15]
    canvas.drawCircle(Offset.zero, 0.12, paint);
    canvas.drawCircle(Offset.zero, 0.01, Paint()..color = const Color(0xCC00FFFF)..style = PaintingStyle.fill);

    // Crosshair ticks
    canvas.drawLine(const Offset(-0.2, 0), const Offset(-0.14, 0), paint);
    canvas.drawLine(const Offset(0.14, 0), const Offset(0.2, 0), paint);
    canvas.drawLine(const Offset(0, -0.2), const Offset(0, -0.14), paint);
    canvas.drawLine(const Offset(0, 0.14), const Offset(0, 0.2), paint);

    // Speedometer and altimeter readouts
    final speed = 12.0;
    final pos = cameraRig.position;
    final alt = pos.y + 100.0; // Simulated altitude

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'SPEED: ${speed.toStringAsFixed(1)} m/s\nALT: ${alt.toStringAsFixed(1)}m\nCOORDS: X=${pos.x.toStringAsFixed(0)} Y=${pos.y.toStringAsFixed(0)} Z=${pos.z.toStringAsFixed(0)}',
        style: const TextStyle(
          color: Color(0xFF00FFFF),
          fontSize: 16.0,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Scale canvas back to pixel space temporarily to draw UI text sharply
    canvas.save();
    canvas.translate(0.25, -0.2); // position in NDC
    canvas.scale(1.0 / 400.0, -1.0 / 400.0); // reverse scale and Y flip
    textPainter.paint(canvas, Offset.zero);
    canvas.restore();

    // Scan for planets in range and render tracking box around them
    for (final planet in planets) {
      final pPos = planet.worldPosition;
      final dist = (pPos - cameraRig.position).length;

      final clip = viewProjection * Vector4(pPos.x, pPos.y, pPos.z, 1.0);
      if (clip.w <= 0.001) continue;

      final ndcX = clip.x / clip.w;
      final ndcY = clip.y / clip.w;

      // Draw tracking brackets if planet is in front
      final size = (20.0 / clip.w).clamp(0.02, 0.25);
      final r = size / 2.0;

      final pPaint = Paint()
        ..color = const Color(0xCCFFAA00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5 / 400.0;

      // Draw corner brackets
      canvas.drawPath(
        Path()
          ..moveTo(ndcX - r, ndcY - r + r * 0.4)
          ..lineTo(ndcX - r, ndcY - r)
          ..lineTo(ndcX - r + r * 0.4, ndcY - r),
        pPaint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(ndcX + r, ndcY - r + r * 0.4)
          ..lineTo(ndcX + r, ndcY - r)
          ..lineTo(ndcX + r - r * 0.4, ndcY - r),
        pPaint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(ndcX - r, ndcY + r - r * 0.4)
          ..lineTo(ndcX - r, ndcY + r)
          ..lineTo(ndcX - r + r * 0.4, ndcY + r),
        pPaint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(ndcX + r, ndcY + r - r * 0.4)
          ..lineTo(ndcX + r, ndcY + r)
          ..lineTo(ndcX + r - r * 0.4, ndcY + r),
        pPaint,
      );

      // Print distance
      final distPainter = TextPainter(
        text: TextSpan(
          text: '${planet.name} [${dist.toStringAsFixed(0)}m]',
          style: const TextStyle(
            color: Color(0xFFFFAA00),
            fontSize: 11.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(ndcX - distPainter.width / 800.0, ndcY + r + 0.02);
      canvas.scale(1.0 / 400.0, -1.0 / 400.0);
      distPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }
}

class SpaceFlightDemo extends VRDemo {
  final List<LitMeshNode> planets = [];
  late final StarfieldNode starfield;
  late final CockpitHudNode hud;

  SpaceFlightDemo(super.engine);

  @override
  void init() {
    engine.cameraRig.position = Vector3(0, 0, 0);

    // Ambient light setup
    final light = Light.ambient(intensity: 0.15);
    engine.scene.add(light);
    nodes.add(light);

    // Directional light representing distant Sun
    final sun = Light.directional(direction: Vector3(-1.0, -0.5, -1.0), intensity: 1.0);
    engine.scene.add(sun);
    nodes.add(sun);

    // Starfield background
    starfield = StarfieldNode(cameraRig: engine.cameraRig);
    engine.scene.add(starfield);
    nodes.add(starfield);

    // Blue/Green Earth-like Planet
    final earth = LitMeshNode(
      name: 'TERRA',
      geometry: SphereGeometry(radius: 5.0, segments: 16),
      material: VRMaterial(color: const Color(0xFF0F766E), metallic: 0.5, roughness: 0.5),
    )..transform.position = Vector3(15, 2, -45)
     ..onTransformChanged();
    engine.scene.add(earth);
    nodes.add(earth);
    planets.add(earth);

    // Red Mars-like Planet
    final mars = LitMeshNode(
      name: 'ARES',
      geometry: SphereGeometry(radius: 3.5, segments: 16),
      material: VRMaterial(color: const Color(0xFFC2410C), metallic: 0.7, roughness: 0.6),
    )..transform.position = Vector3(-25, -5, -75)
     ..onTransformChanged();
    engine.scene.add(mars);
    nodes.add(mars);
    planets.add(mars);

    // Large Brown Jupiter-like Gas Giant
    final jupiter = LitMeshNode(
      name: 'ZEUS',
      geometry: SphereGeometry(radius: 12.0, segments: 24),
      material: VRMaterial(color: const Color(0xFF78350F), metallic: 0.1, roughness: 0.9),
    )..transform.position = Vector3(20, 20, -130)
     ..onTransformChanged();
    engine.scene.add(jupiter);
    nodes.add(jupiter);
    planets.add(jupiter);

    // Add HUD
    hud = CockpitHudNode(cameraRig: engine.cameraRig, planets: planets);
    engine.scene.add(hud);
    nodes.add(hud);
  }

  @override
  void update(double dt) {
    // Constant flight speed forward
    engine.cameraRig.position += engine.cameraRig.headTransform.forward * (10.0 * dt);

    // Rotate planets slowly
    for (final planet in planets) {
      planet.transform.rotate(Quaternion.axisAngle(Vector3(0, 1, 0), 0.15 * dt));
      planet.onTransformChanged();
    }

    // Reset position if we fly too far (avoid precision loss)
    if (engine.cameraRig.position.length > 150.0) {
      engine.cameraRig.position = Vector3.zero();
    }
  }
}

// ============================================================================
// 3. VR Cinema & Video Player
// ============================================================================
class VRCinemaDemo extends VRDemo {
  final List<LitMeshNode> screenSegments = [];
  double playTime = 0.0;
  bool isPlaying = true;
  bool isMuted = false;
  late final SpatialText progressLabel;
  late final SpatialButton playButton;
  late final SpatialButton muteButton;

  VRCinemaDemo(super.engine);

  @override
  void init() {
    engine.cameraRig.position = Vector3(0, 0, 0);

    // Ambient light - extremely dim
    final ambient = Light.ambient(intensity: 0.08);
    engine.scene.add(ambient);
    nodes.add(ambient);

    // Curved Screen geometry construction
    const double radius = 8.0;
    const double width = 2.4;
    const double height = 4.5;
    const int segmentsCount = 5;
    const double totalArc = pi / 2.8; // 64 degree curve arc

    for (var i = 0; i < segmentsCount; i++) {
      final t = i / (segmentsCount - 1);
      final angle = -totalArc / 2 + t * totalArc;
      
      final x = sin(angle) * radius;
      final z = -cos(angle) * radius;

      final segment = LitMeshNode(
        name: 'cinema_screen_$i',
        geometry: PlaneGeometry(width: width, height: height),
        material: VRMaterial(
          color: const Color(0xFF020617),
          emissive: const Color(0xFF0F172A),
          opacity: 1.0,
        ),
      );
      segment.transform.position = Vector3(x, 1.8, z);
      segment.transform.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), -angle);
      segment.onTransformChanged();

      engine.scene.add(segment);
      nodes.add(segment);
      screenSegments.add(segment);
    }

    // Cinema Chairs (visuals behind viewer)
    for (var x = -1.6; x <= 1.6; x += 0.8) {
      final chair = LitMeshNode(
        name: 'chair_$x',
        geometry: CubeGeometry(size: 0.6),
        material: VRMaterial(color: const Color(0xFF451A03), roughness: 0.7),
      )..transform.position = Vector3(x, -1.2, 1.8)
       ..onTransformChanged();
      engine.scene.add(chair);
      nodes.add(chair);
    }

    // UI Progress Label
    progressLabel = SpatialText(
      name: 'cinema_label',
      cameraRig: engine.cameraRig,
      text: 'Cosmic Voyage - 00:00 / 05:00',
      fontSize: 2.2,
      color: const Color(0xFF00FFCC),
      lockY: true,
    )..transform.position = Vector3(0, 0.2, -3.2)
     ..onTransformChanged();
    engine.scene.add(progressLabel);
    nodes.add(progressLabel);

    // Play/Pause button
    playButton = SpatialButton(
      name: 'btn_play',
      transform: Transform3D(
        position: Vector3(-0.65, -0.2, -3.0),
        scale: Vector3(1.0, 0.28, 0.05),
      ),
      label: 'PLAY',
      panel: SpatialPanel(
        cameraRig: engine.cameraRig,
        panelWidth: 1.0,
        panelHeight: 0.28,
        backgroundColor: const Color(0xE01E293B),
        borderColor: const Color(0xFF00FFCC),
      ),
      onPress: (_) => _togglePlay(),
    );
    engine.scene.add(playButton);
    nodes.add(playButton);

    // Mute button
    muteButton = SpatialButton(
      name: 'btn_mute',
      transform: Transform3D(
        position: Vector3(0.65, -0.2, -3.0),
        scale: Vector3(1.0, 0.28, 0.05),
      ),
      label: 'MUTE',
      panel: SpatialPanel(
        cameraRig: engine.cameraRig,
        panelWidth: 1.0,
        panelHeight: 0.28,
        backgroundColor: const Color(0xE01E293B),
        borderColor: const Color(0xFF00FFCC),
      ),
      onPress: (_) => _toggleMute(),
    );
    engine.scene.add(muteButton);
    nodes.add(muteButton);
  }

  void _togglePlay() {
    isPlaying = !isPlaying;
    playButton.label = isPlaying ? 'PAUSE' : 'PLAY';
  }

  void _toggleMute() {
    isMuted = !isMuted;
    muteButton.label = isMuted ? 'UNMUTE' : 'MUTE';
  }

  @override
  void update(double dt) {
    if (isPlaying) {
      playTime += dt;
      if (playTime > 300.0) playTime = 0; // Wrap 5 minutes

      // Animate cinematic light projections on the curved screen segments
      for (var i = 0; i < screenSegments.length; i++) {
        final node = screenSegments[i];
        final factor = 0.5 + 0.5 * sin(playTime * 1.5 + i * 0.7);
        final r = (0.1 * factor + 0.9 * factor * sin(playTime * 0.4).abs());
        final g = (0.2 * factor + 0.8 * factor * cos(playTime * 0.3).abs());
        final b = (0.5 * factor + 0.5 * factor * sin(playTime * 0.6 + 1.2).abs());

        node.material.color = Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());
        node.material.emissive = node.material.color.withValues(alpha: 0.75);
      }

      // Update timer texts
      final mins = (playTime ~/ 60).toString().padLeft(2, '0');
      final secs = (playTime % 60).toInt().toString().padLeft(2, '0');
      progressLabel.text = 'Cosmic Voyage - $mins:$secs / 05:00';
    }
  }
}

// ============================================================================
// 4. WiFi CSI Trajectory Radar Demo
// ============================================================================
class WifiRadarDemo extends VRDemo {
  late final WifiSensingSystem wifiSystem;
  late final WifiRadarNode radarNode;
  late final LitMeshNode scannerLine;
  late final SpatialText overlayInfo;
  
  final List<HologramMeshNode> hologramParts = [];
  double elapsed = 0.0;

  WifiRadarDemo(super.engine);

  @override
  void init() {
    engine.cameraRig.position = Vector3(0, 0, 0);

    // Dim sci-fi blue ambient light
    final ambient = Light.ambient(intensity: 0.18);
    engine.scene.add(ambient);
    nodes.add(ambient);

    // Green Radar floor sensor node
    radarNode = WifiRadarNode(
      pulseSpeed: 3.5,
      radarColor: const Color(0xFF10B981),
      showGrid: true,
    )..transform.position = Vector3(0, -1.5, -3.0)
     ..onTransformChanged();
    engine.scene.add(radarNode);
    nodes.add(radarNode);

    // Scanning Radar line
    scannerLine = LitMeshNode(
      name: 'radar_scanner_line',
      geometry: CubeGeometry(size: 1.0),
      material: VRMaterial(color: const Color(0xFF10B981), emissive: const Color(0xFF10B981), opacity: 0.7),
    );
    scannerLine.transform.position = Vector3(0, -1.48, -3.0);
    scannerLine.transform.scale = Vector3(0.04, 0.01, 3.8); // Radial scan line
    scannerLine.onTransformChanged();
    engine.scene.add(scannerLine);
    nodes.add(scannerLine);

    // Human Hologram Mesh nodes (Torso + Head)
    final bodyHolo = HologramMeshNode(
      name: 'holo_torso',
      geometry: CylinderGeometry(radius: 0.25, height: 1.0, segments: 10),
      hologramColor: const Color(0xFF06B6D4), // Cyan
    );
    engine.scene.add(bodyHolo);
    nodes.add(bodyHolo);
    hologramParts.add(bodyHolo);

    final headHolo = HologramMeshNode(
      name: 'holo_head',
      geometry: SphereGeometry(radius: 0.16, segments: 8),
      hologramColor: const Color(0xFF06B6D4),
    );
    engine.scene.add(headHolo);
    nodes.add(headHolo);
    hologramParts.add(headHolo);

    // Holographic info overlay
    overlayInfo = SpatialText(
      name: 'radar_overlay',
      cameraRig: engine.cameraRig,
      text: 'WiFi CSI Sensing:\nSubject: subject_alpha\nVitals: 16.0 BPM\nSignal Strength: High',
      fontSize: 1.5,
      color: const Color(0xFF10B981),
      lockY: true,
    )..transform.position = Vector3(0, 0.4, -3.0)
     ..onTransformChanged();
    engine.scene.add(overlayInfo);
    nodes.add(overlayInfo);

    // Start simulated background signal tracking Isolate
    wifiSystem = WifiSensingSystem();
    wifiSystem.start();
  }

  @override
  void update(double dt) {
    elapsed += dt;

    // Update global hologram times for glitches and shell rendering
    HologramMeshNode.time = elapsed;
    WifiRadarNode.time = elapsed;

    // Feed simulated Channel State Information (CSI) subcarriers into processing isolate
    final timeMs = DateTime.now().millisecondsSinceEpoch;
    final amplitudes = List.generate(
      32,
      (idx) => 1.2 + sin(elapsed * 2.0 + idx * 0.1) * 0.4 + (Random().nextDouble() - 0.5) * 0.1,
    );
    wifiSystem.feedRawCsi(CsiFrame(timestamp: timeMs, amplitudes: amplitudes));

    // Rotate physical scan sweep line around Y-axis
    scannerLine.transform.rotate(Quaternion.axisAngle(Vector3(0, 1, 0), 2.2 * dt));
    scannerLine.onTransformChanged();

    // Query active tracked subjects
    if (wifiSystem.trackedSubjects.isNotEmpty) {
      final subject = wifiSystem.trackedSubjects.first;
      
      // Update hologram part positions based on raw trilaterated coordinates
      final basePos = subject.position;
      hologramParts[0].transform.position = basePos + Vector3(0, 0.5, 0); // torso
      hologramParts[0].onTransformChanged();

      hologramParts[1].transform.position = basePos + Vector3(0, 1.15, 0); // head
      hologramParts[1].onTransformChanged();

      // Update info billboard overlay text
      final state = subject.isMoving ? 'WALKING' : 'STATIONARY';
      overlayInfo.text = 'WiFi CSI Sensing Status: ACTIVE\n'
                         'Tracked: subject_alpha (Dist: ${(basePos - Vector3(0, -1.5, -3.0)).length.toStringAsFixed(2)}m)\n'
                         'Activity: $state\n'
                         'Respiration: ${subject.respirationRate.toStringAsFixed(1)} BPM (Normal)';
    }
  }

  @override
  void dispose() {
    wifiSystem.dispose();
    hologramParts.clear();
    super.dispose();
  }
}

// ============================================================================
// 5. Grid/Latitude Demo (Original Example Code)
// ============================================================================
class GridDemo extends VRDemo {
  static const double _r = 50.0;

  GridDemo(super.engine);

  @override
  void init() {
    // Lights
    final ambient = Light.ambient(intensity: 0.5);
    engine.scene.add(ambient);
    nodes.add(ambient);

    final dir = Light.directional(direction: Vector3(-0.3, -1, -0.5), intensity: 0.35);
    engine.scene.add(dir);
    nodes.add(dir);

    // Ground
    final ground = LitMeshNode(
      name: 'gnd',
      geometry: PlaneGeometry(width: 120, height: 120),
      material: VRMaterial(color: const Color(0xFF060610)),
    )..transform.position = Vector3(0, -1.6, 0)
     ..onTransformChanged();
    engine.scene.add(ground);
    nodes.add(ground);

    // Ring, Meridian, Beam, Card, Label methods
    _ring('eq', _r, 0, 0.2, const Color(0xFFFFDD00), const Color(0xFFBB9900));
    _ring('l30', _r * 0.866, _r * 0.5, 0.08, const Color(0xFF00CCFF), const Color(0xFF0077AA));
    _ring('l-30', _r * 0.866, -_r * 0.5, 0.08, const Color(0xFF00CCFF), const Color(0xFF0077AA));
    _ring('l60', _r * 0.5, _r * 0.866, 0.06, const Color(0xFF0088DD), const Color(0xFF004477));
    _ring('l-60', _r * 0.5, -_r * 0.866, 0.06, const Color(0xFF0088DD), const Color(0xFF004477));
    _ring('l80', _r * 0.174, _r * 0.985, 0.04, const Color(0xFF6666CC), const Color(0xFF333366));
    _ring('l-80', _r * 0.174, -_r * 0.985, 0.04, const Color(0xFF6666CC), const Color(0xFF333366));

    for (var j = 0; j < 6; j++) {
      final lon = j * pi / 6;
      final prime = j == 0;
      final c = prime ? const Color(0xFF55CCFF) : const Color(0xFF2288CC);
      final e = prime ? const Color(0xFF337799) : const Color(0xFF114466);
      final t = prime ? 0.18 : 0.08;

      for (var i = 0; i < 10; i++) {
        final a1 = -pi / 2 + i * pi / 10;
        final a2 = -pi / 2 + (i + 1) * pi / 10;
        _meridianSeg('m${j}_$i', lon, a1, a2, c, e, t);
      }
    }

    _beam('aX', const Color(0xFFFF4444), const Color(0xFFAA2222), Vector3(_r * 2, 0.15, 0.15));
    _beam('aY', const Color(0xFFCCCCFF), const Color(0xFF7777AA), Vector3(0.15, _r * 2, 0.15));
    _beam('aZ', const Color(0xFF4466FF), const Color(0xFF2233AA), Vector3(0.15, 0.15, _r * 2));

    _card('N', const Color(0xFFFF3333), Vector3(0, 0, -_r), 2.5);
    _card('S', const Color(0xFFFFAA00), Vector3(0, 0, _r), 2.0);
    _card('E', const Color(0xFF00EEFF), Vector3(_r, 0, 0), 2.0);
    _card('W', const Color(0xFFFF55FF), Vector3(-_r, 0, 0), 2.0);
    _card('Up', const Color(0xFFFFFFFF), Vector3(0, _r, 0), 1.2);
    _card('Dn', const Color(0xFF888888), Vector3(0, -_r, 0), 0.8);

    _label('tN', 'NORTH', Vector3(0, 2, -_r + 5), 3.5, const Color(0xFFFF4444));
    _label('tS', 'SOUTH', Vector3(0, 2, _r - 5), 3.0, const Color(0xFFFFAA00));
    _label('tE', 'EAST', Vector3(_r - 5, 2, 0), 3.0, const Color(0xFF00EEFF));
    _label('tW', 'WEST', Vector3(-_r + 5, 2, 0), 3.0, const Color(0xFFFF55FF));
    _label('tU', 'ZENITH', Vector3(0, _r - 5, 0), 2.5, const Color(0xFFFFFFFF));
    _label('tD', 'NADIR', Vector3(0, -_r + 5, 0), 2.0, const Color(0xFF888888));

    _label('t30', '30\u00b0N', Vector3(_r * 0.866 + 2, _r * 0.5, 0), 2.0, const Color(0xFF00CCFF));
    _label('t-30', '30\u00b0S', Vector3(_r * 0.866 + 2, -_r * 0.5, 0), 2.0, const Color(0xFF00CCFF));
    _label('t60', '60\u00b0N', Vector3(_r * 0.5 + 2, _r * 0.866, 0), 1.8, const Color(0xFF0088DD));
    _label('t-60', '60\u00b0S', Vector3(_r * 0.5 + 2, -_r * 0.866, 0), 1.8, const Color(0xFF0088DD));
    _label('tEq', 'EQUATOR', Vector3(_r + 3, 2, 0), 2.5, const Color(0xFFFFDD00));
  }

  void _ring(String n, double r, double y, double h, Color c, Color e) {
    final ring = LitMeshNode(
      name: n,
      geometry: CylinderGeometry(radius: r, height: h, segments: 36),
      material: VRMaterial(color: c, emissive: e, metallic: 0.5),
    )
      ..transform.position = Vector3(0, y, 0)
      ..onTransformChanged();
    engine.scene.add(ring);
    nodes.add(ring);
  }

  void _meridianSeg(String n, double lon, double a1, double a2, Color c, Color e, double thick) {
    final p1 = Vector3(_r * cos(a1) * sin(lon), _r * sin(a1), _r * cos(a1) * cos(lon));
    final p2 = Vector3(_r * cos(a2) * sin(lon), _r * sin(a2), _r * cos(a2) * cos(lon));
    final mid = (p1 + p2) * 0.5;
    final dir = p2 - p1;
    final seg = LitMeshNode(
      name: n,
      geometry: CubeGeometry(size: 1),
      material: VRMaterial(color: c, emissive: e, metallic: 0.4),
    );
    seg.transform.position = mid;
    seg.transform.scale = Vector3(thick, dir.length, thick);
    final up = Vector3(0, 1, 0);
    final dn = dir.normalized();
    final ax = up.cross(dn);
    if (ax.length > 0.001) {
      seg.transform.rotation = Quaternion.axisAngle(
        ax.normalized(),
        acos(up.dot(dn).clamp(-1.0, 1.0)),
      );
    }
    seg.onTransformChanged();
    engine.scene.add(seg);
    nodes.add(seg);
  }

  void _beam(String n, Color c, Color e, Vector3 s) {
    final beam = LitMeshNode(
      name: n,
      geometry: CubeGeometry(size: 1),
      material: VRMaterial(color: c, emissive: e),
    )
      ..transform.scale = s
      ..onTransformChanged();
    engine.scene.add(beam);
    nodes.add(beam);
  }

  void _card(String n, Color c, Vector3 p, double sz) {
    final card = LitMeshNode(
      name: 'c$n',
      geometry: SphereGeometry(radius: sz, segments: 8),
      material: VRMaterial(
        color: c,
        emissive: Color.fromARGB(120, (c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()),
        metallic: 0.7,
      ),
    )
      ..transform.position = p
      ..onTransformChanged();
    engine.scene.add(card);
    nodes.add(card);
  }

  void _label(String n, String text, Vector3 p, double sz, Color c) {
    final label = SpatialText(
      name: n,
      cameraRig: engine.cameraRig,
      text: text,
      fontSize: sz,
      color: c,
      lockY: true,
    );
    label.transform.position = p;
    label.onTransformChanged();
    engine.scene.add(label);
    nodes.add(label);
  }

  @override
  void update(double dt) {
    final t = engine.frameCount * 0.016;

    // Pulse cardinals
    for (final l in ['cN', 'cS', 'cE', 'cW', 'cUp', 'cDn']) {
      final n = engine.scene.root.findChild(l);
      if (n != null) {
        n.transform.scale = Vector3.all(1.0 + sin(t * 1.5 + n.hashCode.toDouble()) * 0.06);
        n.onTransformChanged();
      }
    }
  }
}
