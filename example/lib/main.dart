import 'dart:async';
import 'dart:math';

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

enum DemoType {
  grid,
  physics,
  space,
  cinema,
  radar,
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

  // Active Demo management
  late VRDemo _activeDemo;
  DemoType _currentDemoType = DemoType.grid;
  SpatialText? _statsLabel;

  // Step detection
  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _fM = 9.81, _pM = 9.81;
  bool _rising = false;
  int _lastStep = 0;

  @override
  void initState() {
    super.initState();
    engine = VREngine();
    engine.cameraRig.position = Vector3(0, 0, 0);
    engine.cameraRig.lookAt(Vector3(0, 0, -1));
    engine.cameraRig.far = 150;

    // Load first demo (original grid)
    _activeDemo = GridDemo(engine);
    _activeDemo.init();
    _buildDashboard();

    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(_onAccel);

    engine.onUpdate = _animate;
    engine.enableHeadTracking(sensitivity: 0.025);
    engine.enableGazePointer(dwellDuration: 1.5);
    engine.start();

    _ticker = createTicker((_) => _repaint.notify())..start();
  }

  void _switchDemo(DemoType type) {
    _activeDemo.dispose();
    engine.scene.clear();

    _currentDemoType = type;
    switch (type) {
      case DemoType.grid:
        _activeDemo = GridDemo(engine);
        break;
      case DemoType.physics:
        _activeDemo = PhysicsPlaygroundDemo(engine);
        break;
      case DemoType.space:
        _activeDemo = SpaceFlightDemo(engine);
        break;
      case DemoType.cinema:
        _activeDemo = VRCinemaDemo(engine);
        break;
      case DemoType.radar:
        _activeDemo = WifiRadarDemo(engine);
        break;
    }

    _activeDemo.init();
    _buildDashboard();
  }

  void _rebuildAll() {
    _switchDemo(_currentDemoType);
  }

  void _buildDashboard() {
    final dashboardRoot = Node(name: 'dashboard_root');
    // Place the dashboard floating to the left of the center vision
    dashboardRoot.transform.position = Vector3(-3.0, 0.6, -4.5);
    dashboardRoot.onTransformChanged();
    engine.scene.add(dashboardRoot);

    // Background Panel behind dashboard
    final bgPanel = SpatialPanel(
      cameraRig: engine.cameraRig,
      panelWidth: 2.2,
      panelHeight: 2.7,
      backgroundColor: const Color(0xEE0B1329),
      borderColor: const Color(0xFF1E293B),
      borderWidth: 2.0,
      cornerRadius: 12.0,
    );
    bgPanel.transform.position = Vector3(0, 0, -0.05);
    bgPanel.onTransformChanged();
    dashboardRoot.addChild(bgPanel);

    // Dashboard Title
    final title = SpatialText(
      cameraRig: engine.cameraRig,
      text: 'VRLIZATE 1.4.0 DASHBOARD',
      fontSize: 1.8,
      color: const Color(0xFF00FFCC),
      fontWeight: FontWeight.bold,
    );
    title.transform.position = Vector3(0, 1.15, 0);
    title.onTransformChanged();
    dashboardRoot.addChild(title);

    // 1. Grid Demo Selector Button
    _createDashboardButton(
      dashboardRoot,
      label: '1. Grid Demo',
      position: Vector3(-0.5, 0.72, 0),
      onPress: () => _switchDemo(DemoType.grid),
    );

    // 2. Physics Selector Button
    _createDashboardButton(
      dashboardRoot,
      label: '2. Physics',
      position: Vector3(0.5, 0.72, 0),
      onPress: () => _switchDemo(DemoType.physics),
    );

    // 3. Space Flight Selector Button
    _createDashboardButton(
      dashboardRoot,
      label: '3. Space Flight',
      position: Vector3(-0.5, 0.32, 0),
      onPress: () => _switchDemo(DemoType.space),
    );

    // 4. VR Cinema Selector Button
    _createDashboardButton(
      dashboardRoot,
      label: '4. VR Cinema',
      position: Vector3(0.5, 0.32, 0),
      onPress: () => _switchDemo(DemoType.cinema),
    );

    // 5. WiFi CSI Radar Selector Button
    _createDashboardButton(
      dashboardRoot,
      label: '5. WiFi CSI Radar',
      position: Vector3(-0.5, -0.08, 0),
      onPress: () => _switchDemo(DemoType.radar),
    );

    // Toggle Lens Distortion Button
    final distState = engine.renderPass.enableLensDistortion ? 'ON' : 'OFF';
    _createDashboardButton(
      dashboardRoot,
      label: 'Lens Dist: $distState',
      position: Vector3(0.5, -0.08, 0),
      onPress: () {
        engine.renderPass.enableLensDistortion = !engine.renderPass.enableLensDistortion;
        _rebuildAll();
      },
    );

    // Toggle Chromatic Aberration Button
    final chromaState = engine.renderPass.enableChromaticAberration ? 'ON' : 'OFF';
    _createDashboardButton(
      dashboardRoot,
      label: 'Chromatic: $chromaState',
      position: Vector3(-0.5, -0.48, 0),
      onPress: () {
        engine.renderPass.enableChromaticAberration = !engine.renderPass.enableChromaticAberration;
        _rebuildAll();
      },
    );

    // FSR Scale Button
    final fsrScale = engine.renderPass.fsrScale;
    _createDashboardButton(
      dashboardRoot,
      label: 'FSR Scale: ${fsrScale.toStringAsFixed(2)}x',
      position: Vector3(0.5, -0.48, 0),
      onPress: () {
        final current = engine.renderPass.fsrScale;
        if (current == 1.0) {
          engine.renderPass.fsrScale = 0.75;
        } else if (current == 0.75) {
          engine.renderPass.fsrScale = 0.5;
        } else {
          engine.renderPass.fsrScale = 1.0;
        }
        _rebuildAll();
      },
    );

    // Live Metrics HUD
    _statsLabel = SpatialText(
      cameraRig: engine.cameraRig,
      text: 'FPS: 0.0 | Frame: 0.0ms\nRendered: 0 | Culled: 0',
      fontSize: 1.4,
      color: const Color(0xFF94A3B8),
    );
    _statsLabel!.transform.position = Vector3(0, -0.98, 0);
    _statsLabel!.onTransformChanged();
    dashboardRoot.addChild(_statsLabel!);
  }

  void _createDashboardButton(
    Node parent, {
    required String label,
    required Vector3 position,
    required VoidCallback onPress,
  }) {
    final btn = SpatialButton(
      name: 'dash_btn_${label.replaceAll(' ', '_')}',
      transform: Transform3D(
        position: position,
        scale: Vector3(0.95, 0.3, 0.05),
      ),
      label: label,
      panel: SpatialPanel(
        cameraRig: engine.cameraRig,
        panelWidth: 0.95,
        panelHeight: 0.3,
        backgroundColor: const Color(0xDD1E293B),
        borderColor: const Color(0xFF334155),
        borderWidth: 1.5,
        cornerRadius: 6.0,
      ),
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
        engine.cameraRig.position += (Vector3(f.x, 0, f.z)..normalize()) * 0.4;
      }
      _rising = false;
    }
    _pM = _fM;
  }

  // ─── Animation Loop ───
  void _animate(double dt) {
    // Update the active VR demo state
    _activeDemo.update(dt);

    // Update real-time performance indicators on the dashboard
    if (_statsLabel != null) {
      _statsLabel!.text = 'FPS: ${engine.fps.toStringAsFixed(1)} | Frame: ${engine.frameTimeMs.toStringAsFixed(1)}ms\n'
                          'Rendered Nodes: ${engine.renderedCount} | Culled: ${engine.culledCount}';
    }
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _ticker.dispose();
    _activeDemo.dispose();
    engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (_activeDemo is PhysicsPlaygroundDemo) {
            (_activeDemo as PhysicsPlaygroundDemo).handleTap();
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
