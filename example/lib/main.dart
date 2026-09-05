import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart' hide Colors;
import 'package:vrlizate/vrlizate.dart';

import 'demos.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _App()));
}

enum AppRoute { home, grid, physics, space, cinema, radar }

class _HomeAction {
  final String label;
  final VoidCallback onPress;

  const _HomeAction(this.label, this.onPress);
}

// ═══════════════════════════════════════════════════════════════
// Zone detection constants (from Meta/Google VR research)
// ═══════════════════════════════════════════════════════════════
enum ViewZone { front, left, right, up, down, behind }

class ZoneDetector {
  /// Computes which zone the camera is looking toward.
  /// Uses dot product of forward vector vs world directions.
  static ViewZone detect(Vector3 forward) {
    final hAngle = atan2(forward.x, -forward.z) * 180 / pi; // -180..180
    final vAngle = asin(forward.y.clamp(-1.0, 1.0)) * 180 / pi; // -90..90

    if (vAngle > 40) return ViewZone.up;
    if (vAngle < -35) return ViewZone.down;

    final absH = hAngle.abs();
    if (absH < 55) return ViewZone.front;
    if (absH > 135) return ViewZone.behind;
    return hAngle > 0 ? ViewZone.right : ViewZone.left;
  }
}

// ═══════════════════════════════════════════════════════════════

class _App extends StatefulWidget {
  const _App();
  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> with SingleTickerProviderStateMixin {
  late final VREngine engine;
  late final Ticker _ticker;
  final _repaint = _Notifier();

  // Spatial route management
  VRDemo? _activeDemo;
  AppRoute _currentRoute = AppRoute.home;
  final List<AppRoute> _routeHistory = [];
  SpatialText? _statsLabel;

  // Step detection
  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _fM = 9.81, _pM = 9.81;
  bool _rising = false;
  int _lastStep = 0;

  bool get _supportsMotionSensors =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    engine = VREngine(
      scene: VrlizateScene(
        quality: VrlizateSceneQuality.high,
        rayTracingMode: VrlizateRayTracingMode.hybridObjectSpace,
        maxRayQueriesPerFrame: 24,
      ),
    );
    engine.cameraRig.position = Vector3(0, 0, 0);
    engine.cameraRig.lookAt(Vector3(0, 0, -1));
    engine.cameraRig.far = 150;

    _buildHome();
    _buildHomeBar();

    engine.onUpdate = _animate;
    if (_supportsMotionSensors) {
      _accelSub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 20),
      ).listen(_onAccel);
      // The current tracker is calibrated in radians at 1:1 scale. Values
      // tuned for the pre-1.6 attenuated tracker make the menu feel fixed.
      engine.enableHeadTracking();
    }
    engine.enableGazePointer(dwellDuration: 1.5);
    engine.start();

    _ticker = createTicker((_) => _repaint.notify())..start();
  }

  void _navigateTo(
    AppRoute route, {
    bool rememberCurrent = true,
    bool forceRebuild = false,
  }) {
    if (route == _currentRoute && !forceRebuild) return;

    if (rememberCurrent && route != _currentRoute) {
      _routeHistory.add(_currentRoute);
    }

    _activeDemo?.dispose();
    _activeDemo = null;
    engine.scene.clear();
    _statsLabel = null;
    _currentRoute = route;

    // Every spatial route starts from a predictable, comfortable origin.
    engine.cameraRig.position = Vector3.zero();
    engine.cameraRig.recenter();

    if (route == AppRoute.home) {
      _buildHome();
    } else {
      _activeDemo = _createDemo(route)..init();
      _buildBackArrow();
    }

    _buildHomeBar();
    engine.gazePointer?.resetAdaptation();
  }

  VRDemo _createDemo(AppRoute route) {
    return switch (route) {
      AppRoute.grid => GridDemo(engine),
      AppRoute.physics => PhysicsPlaygroundDemo(engine),
      AppRoute.space => SpaceFlightDemo(engine),
      AppRoute.cinema => VRCinemaDemo(engine),
      AppRoute.radar => WifiRadarDemo(engine),
      AppRoute.home => throw StateError('Home is not a VR demo.'),
    };
  }

  void _goBack() {
    if (_routeHistory.isEmpty) {
      _navigateTo(AppRoute.home, rememberCurrent: false);
      return;
    }

    final previous = _routeHistory.removeLast();
    _navigateTo(previous, rememberCurrent: false);
  }

  void _rebuildAll() {
    _navigateTo(_currentRoute, rememberCurrent: false, forceRebuild: true);
  }

  void _buildHome() {
    engine.scene.backgroundColor = const Color(0xFF07111F);
    engine.scene.fogDensity = 0.04;
    engine.scene.fogColor = const Color(0xFF07111F);

    _buildHomeEnvironment();

    final title = SpatialText(
      cameraRig: engine.cameraRig,
      text: 'VRLIZATE  |  HOME ESPACIAL',
      fontSize: 0.46,
      color: const Color(0xFF00FFCC),
      fontWeight: FontWeight.bold,
    );
    title.transform.position = Vector3(0, 1.48, -4.0);
    title.onTransformChanged();
    engine.scene.add(title);

    final subtitle = SpatialText(
      cameraRig: engine.cameraRig,
      text: 'Camina para acercarte, desliza para mirar y toca para abrir',
      fontSize: 0.20,
      color: const Color(0xFF94A3B8),
    );
    subtitle.transform.position = Vector3(0, 1.22, -4.0);
    subtitle.onTransformChanged();
    engine.scene.add(subtitle);

    _createHomeScreen(
      name: 'home_screen_explore',
      title: 'EXPLORAR',
      subtitle: 'Escenas y movimiento',
      position: Vector3(-1.62, 0.12, -4.15),
      accent: const Color(0xFF38BDF8),
      actions: [
        _HomeAction('GRID 3D', () => _navigateTo(AppRoute.grid)),
        _HomeAction('VUELO ESPACIAL', () => _navigateTo(AppRoute.space)),
      ],
    );

    _createHomeScreen(
      name: 'home_screen_play',
      title: 'EXPERIENCIAS',
      subtitle: 'Interaccion y medios',
      position: Vector3(0, 0.18, -4.0),
      accent: const Color(0xFFA78BFA),
      actions: [
        _HomeAction('FISICA', () => _navigateTo(AppRoute.physics)),
        _HomeAction('CINE VR', () => _navigateTo(AppRoute.cinema)),
      ],
    );

    final distState = engine.renderPass.enableLensDistortion ? 'ON' : 'OFF';
    final chromaState = engine.renderPass.enableChromaticAberration
        ? 'ON'
        : 'OFF';
    final fsrScale = engine.renderPass.fsrScale;
    _createHomeScreen(
      name: 'home_screen_system',
      title: 'SISTEMA',
      subtitle: 'Conexion y calidad',
      position: Vector3(1.62, 0.12, -4.15),
      accent: const Color(0xFF34D399),
      actions: [
        _HomeAction('RADAR WIFI', () => _navigateTo(AppRoute.radar)),
        _HomeAction('LENTE: $distState', () {
          engine.renderPass.enableLensDistortion =
              !engine.renderPass.enableLensDistortion;
          _rebuildAll();
        }),
        _HomeAction('CROMA: $chromaState', () {
          engine.renderPass.enableChromaticAberration =
              !engine.renderPass.enableChromaticAberration;
          _rebuildAll();
        }),
        _HomeAction('FSR: ${fsrScale.toStringAsFixed(2)}x', () {
          final current = engine.renderPass.fsrScale;
          engine.renderPass.fsrScale = switch (current) {
            1.0 => 0.75,
            0.75 => 0.5,
            _ => 1.0,
          };
          _rebuildAll();
        }),
      ],
    );
  }

  void _buildHomeEnvironment() {
    engine.scene.add(Light.ambient(intensity: 0.24));
    engine.scene.add(
      Light.directional(
        direction: Vector3(-0.4, -1, -0.5),
        color: const Color(0xFFD9F7FF),
        intensity: 1.1,
      ),
    );

    final floor = LitMeshNode(
      name: 'home_floor',
      geometry: PlaneGeometry(width: 18, height: 22, segW: 4, segH: 5),
      material: PBRMaterial(
        color: const Color(0xFF101D31),
        metallic: 0.45,
        roughness: 0.38,
      ),
    );
    floor.transform.position = Vector3(0, -1.5, -5);
    floor.onTransformChanged();
    engine.scene.add(floor);

    for (var index = -4; index <= 4; index++) {
      final guide = LitMeshNode(
        name: 'home_floor_guide_$index',
        geometry: CubeGeometry(),
        material: VRMaterial(
          color: const Color(0xFF164E63),
          emissive: const Color(0xFF0E7490),
          opacity: 0.72,
        ),
      );
      guide.transform.position = Vector3(index * 0.75, -1.47, -5.2);
      guide.transform.scale = Vector3(0.018, 0.015, 8);
      guide.onTransformChanged();
      engine.scene.add(guide);
    }
  }

  void _createHomeScreen({
    required String name,
    required String title,
    required String subtitle,
    required Vector3 position,
    required Color accent,
    required List<_HomeAction> actions,
  }) {
    final screen = Node(name: name);
    screen.transform.position = position;
    screen.onTransformChanged();
    engine.scene.add(screen);

    _addScreenFrame(screen, name: name, accent: accent);

    final surface = SpatialPanel(
      name: '${name}_surface',
      cameraRig: engine.cameraRig,
      panelWidth: 1.42,
      panelHeight: 1.92,
      backgroundColor: const Color(0xF20F1D32),
      borderColor: accent,
      borderWidth: 2.4,
      cornerRadius: 14,
    );
    surface.transform.position = Vector3(0, 0, -0.08);
    surface.onTransformChanged();
    screen.addChild(surface);

    final heading = SpatialText(
      cameraRig: engine.cameraRig,
      text: title,
      fontSize: 0.30,
      color: accent,
      fontWeight: FontWeight.bold,
    );
    heading.transform.position = Vector3(0, 0.72, 0);
    heading.onTransformChanged();
    screen.addChild(heading);

    final caption = SpatialText(
      cameraRig: engine.cameraRig,
      text: subtitle,
      fontSize: 0.17,
      color: const Color(0xFF94A3B8),
    );
    caption.transform.position = Vector3(0, 0.48, 0);
    caption.onTransformChanged();
    screen.addChild(caption);

    final gap = actions.length > 2 ? 0.32 : 0.48;
    final firstY = actions.length > 2 ? 0.25 : 0.18;
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index];
      _createSpatialButton(
        screen,
        name: '${name}_action_$index',
        label: action.label,
        position: Vector3(0, firstY - gap * index, 0),
        width: 1.12,
        height: actions.length > 2 ? 0.24 : 0.32,
        accent: accent,
        onPress: action.onPress,
      );
    }
  }

  void _addScreenFrame(
    Node screen, {
    required String name,
    required Color accent,
  }) {
    final frameMaterial = PBRMaterial(
      color: accent,
      emissive: accent.withValues(alpha: 0.3),
      metallic: 0.82,
      roughness: 0.2,
    );
    final back = LitMeshNode(
      name: '${name}_3d_back',
      geometry: CubeGeometry(),
      material: PBRMaterial(
        color: const Color(0xFF0A1220),
        metallic: 0.55,
        roughness: 0.32,
      ),
    );
    back.transform.position = Vector3(0, 0, -0.12);
    back.transform.scale = Vector3(1.52, 2.02, 0.10);
    back.onTransformChanged();
    screen.addChild(back);

    void addBar(String suffix, Vector3 position, Vector3 scale) {
      final bar = LitMeshNode(
        name: '${name}_frame_$suffix',
        geometry: CubeGeometry(),
        material: frameMaterial,
      );
      bar.transform.position = position;
      bar.transform.scale = scale;
      bar.onTransformChanged();
      screen.addChild(bar);
    }

    addBar('top', Vector3(0, 1.0, -0.02), Vector3(1.58, 0.055, 0.10));
    addBar('bottom', Vector3(0, -1.0, -0.02), Vector3(1.58, 0.055, 0.10));
    addBar('left', Vector3(-0.76, 0, -0.02), Vector3(0.055, 2.0, 0.10));
    addBar('right', Vector3(0.76, 0, -0.02), Vector3(0.055, 2.0, 0.10));
  }

  void _buildBackArrow() {
    final arrow = SpatialNavigationArrow(
      name: 'demo_back_arrow',
      transform: Transform3D(
        position: Vector3(-1.28, 0.92, -2.8),
        scale: Vector3.all(0.72),
      ),
      onPress: (_) => _goBack(),
    );
    engine.scene.add(arrow);

    final label = SpatialText(
      cameraRig: engine.cameraRig,
      text: 'ATRAS',
      fontSize: 0.18,
      color: const Color(0xFFBAE6FD),
      fontWeight: FontWeight.bold,
    );
    label.transform.position = Vector3(-1.02, 0.56, -2.82);
    label.onTransformChanged();
    engine.scene.add(label);
  }

  void _buildHomeBar() {
    final bar = Node(name: 'home_bar');
    bar.transform.position = Vector3(0, -1.03, -2.9);
    bar.onTransformChanged();
    engine.scene.add(bar);

    final surface = SpatialPanel(
      name: 'home_bar_surface',
      cameraRig: engine.cameraRig,
      panelWidth: 3.55,
      panelHeight: 0.66,
      backgroundColor: const Color(0xF20B1324),
      borderColor: const Color(0xFF334155),
      borderWidth: 2,
      cornerRadius: 18,
    );
    surface.transform.position = Vector3(0, 0, -0.08);
    surface.onTransformChanged();
    bar.addChild(surface);

    const destinations = <(AppRoute, String)>[
      (AppRoute.home, 'HOME'),
      (AppRoute.grid, 'GRID'),
      (AppRoute.physics, 'FISICA'),
      (AppRoute.space, 'VUELO'),
      (AppRoute.cinema, 'CINE'),
      (AppRoute.radar, 'RADAR'),
    ];
    for (var index = 0; index < destinations.length; index++) {
      final (route, label) = destinations[index];
      _createSpatialButton(
        bar,
        name: 'home_bar_${route.name}',
        label: label,
        position: Vector3(-1.4 + index * 0.56, 0.10, 0),
        width: 0.49,
        height: 0.26,
        accent: const Color(0xFF22D3EE),
        selected: route == _currentRoute,
        onPress: () => _navigateTo(route),
      );
    }

    _statsLabel = SpatialText(
      cameraRig: engine.cameraRig,
      text: 'FPS 0.0  |  0.0 ms  |  ruta: ${_currentRoute.name}',
      fontSize: 0.13,
      color: const Color(0xFF94A3B8),
    );
    _statsLabel!.transform.position = Vector3(0, -0.20, 0);
    _statsLabel!.onTransformChanged();
    bar.addChild(_statsLabel!);
  }

  void _createSpatialButton(
    Node parent, {
    required String name,
    required String label,
    required Vector3 position,
    required double width,
    required double height,
    required Color accent,
    required VoidCallback onPress,
    bool selected = false,
  }) {
    final btn = SpatialButton(
      name: name,
      transform: Transform3D(
        position: position,
        scale: Vector3(width, height, 0.05),
      ),
      label: label,
      panel: SpatialPanel(
        cameraRig: engine.cameraRig,
        panelWidth: width,
        panelHeight: height,
        borderColor: accent,
        borderWidth: 1.5,
        cornerRadius: 6.0,
      ),
      idleColor: selected ? accent : const Color(0xEB1E293B),
      hoverColor: accent,
      pressColor: const Color(0xFFFFFFFF),
      labelColor: selected ? const Color(0xFF07111F) : const Color(0xFFFFFFFF),
      onPress: (_) => onPress(),
    );
    parent.addChild(btn);
  }

  // ─── Step detection ───
  void _onAccel(AccelerometerEvent e) {
    final m = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _fM = _fM * 0.85 + m * 0.15;
    if (_fM > 11.5) _rising = true;
    if (_rising && _fM < _pM) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastStep >= 300) {
        _lastStep = now;
        final f = engine.cameraRig.headTransform.forward;
        final walkingDirection = Vector3(f.x, 0, f.z);
        if (walkingDirection.length2 > 0.0001) {
          walkingDirection.normalize();
          engine.cameraRig.position += walkingDirection * 0.4;
        }
      }
      _rising = false;
    }
    _pM = _fM;
  }

  // ─── Animation Loop ───
  void _animate(double dt) {
    _activeDemo?.update(dt);

    if (_statsLabel != null) {
      _statsLabel!.text =
          'FPS ${engine.fps.toStringAsFixed(1)}  |  '
          '${engine.frameTimeMs.toStringAsFixed(1)} ms  |  '
          'ruta: ${_currentRoute.name}';
    }
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _ticker.dispose();
    _activeDemo?.dispose();
    engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onPanUpdate: (details) {
          final tracker = engine.headTracker;
          if (tracker != null) {
            tracker.applyTouchDelta(details.delta.dx, details.delta.dy);
          } else {
            engine.cameraRig.rotate(
              -details.delta.dx * 0.005,
              -details.delta.dy * 0.005,
            );
          }
        },
        onDoubleTap: () {
          engine.headTracker?.recenter();
          engine.cameraRig.recenter();
        },
        onTap: () {
          final demo = _activeDemo;
          if (demo is PhysicsPlaygroundDemo) {
            demo.handleTap();
          } else {
            engine.handleTap();
          }
        },
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _P(engine, _repaint),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _P extends CustomPainter {
  final VREngine e;
  _P(this.e, _Notifier n) : super(repaint: n);

  @override
  void paint(Canvas c, Size s) {
    if (s.isEmpty) return;

    // Render stereoscopic side-by-side viewports
    e.renderPass.renderStereo(c, s);

    // Overlay stereoscopically aligned reticles for both eyes
    if (e.gazePointer != null) {
      final halfW = s.width / 2;
      final eyeSize = Size(halfW, s.height);

      // Left eye reticle
      e.gazePointer!.renderReticle(c, eyeSize);

      // Right eye reticle
      c.save();
      c.translate(halfW, 0);
      e.gazePointer!.renderReticle(c, eyeSize);
      c.restore();
    }
  }

  @override
  bool shouldRepaint(_P o) => true;
}

class _Notifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
