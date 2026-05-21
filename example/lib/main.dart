import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart' hide Colors;
import 'package:vrlizate/vrlizate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _App()));
}

// ═══════════════════════════════════════════════════════════════
// Zone detection constants (from Meta/Google VR research)
// ═══════════════════════════════════════════════════════════════
enum ViewZone { front, left, right, up, down, behind }

class _ZoneDetector {
  /// Computes which zone the camera is looking toward.
  /// Uses dot product of forward vector vs world directions.
  static ViewZone detect(Vector3 forward) {
    // Horizontal angle from -Z (default front)
    final hAngle = atan2(forward.x, -forward.z) * 180 / pi; // -180..180
    // Vertical angle
    final vAngle = asin(forward.y.clamp(-1.0, 1.0)) * 180 / pi; // -90..90

    // Vertical zones first (>40° = up/down per Meta research)
    if (vAngle > 40) return ViewZone.up;
    if (vAngle < -35) return ViewZone.down;

    // Horizontal zones (±55° front, ±55-135 sides, rest behind)
    final absH = hAngle.abs();
    if (absH < 55) return ViewZone.front;
    if (absH > 135) return ViewZone.behind;
    return hAngle > 0 ? ViewZone.right : ViewZone.left;
  }

  // ignore: unused_element
  static Color zoneColor(ViewZone zone) => switch (zone) {
    ViewZone.front => const Color(0xFF44FF44),
    ViewZone.left => const Color(0xFF44AAFF),
    ViewZone.right => const Color(0xFFFF44AA),
    ViewZone.up => const Color(0xFFFFDD44),
    ViewZone.down => const Color(0xFFAA44FF),
    ViewZone.behind => const Color(0xFFFF4444),
  };
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

  // ignore: constant_identifier_names
  static const double _R = 50.0;
  // ignore: unused_field
  ViewZone _zone = ViewZone.front;

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
    engine.cameraRig.far = 120;

    _build();

    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(_onAccel);

    engine.onUpdate = _animate;
    engine.enableHeadTracking(sensitivity: 0.025);
    engine.start();
    _ticker = createTicker((_) => _repaint.notify())..start();
  }

  // ═══════════════════════════════════════════════════════════════
  // Scene: ~35 nodes total for maximum performance
  // ═══════════════════════════════════════════════════════════════

  void _build() {
    // ─── EQUATOR — bright gold ring at y=0 ───
    _ring('eq', _R, 0, 0.2, const Color(0xFFFFDD00), const Color(0xFFBB9900));

    // ─── LATITUDE RINGS — proportional radius ───
    // ±30° (Tropics area) — medium rings
    _ring(
      'l30',
      _R * 0.866,
      _R * 0.5,
      0.08,
      const Color(0xFF00CCFF),
      const Color(0xFF0077AA),
    );
    _ring(
      'l-30',
      _R * 0.866,
      -_R * 0.5,
      0.08,
      const Color(0xFF00CCFF),
      const Color(0xFF0077AA),
    );
    // ±60° — smaller rings (clearly smaller than equator)
    _ring(
      'l60',
      _R * 0.5,
      _R * 0.866,
      0.06,
      const Color(0xFF0088DD),
      const Color(0xFF004477),
    );
    _ring(
      'l-60',
      _R * 0.5,
      -_R * 0.866,
      0.06,
      const Color(0xFF0088DD),
      const Color(0xFF004477),
    );
    // ±80° — small polar rings
    _ring(
      'l80',
      _R * 0.174,
      _R * 0.985,
      0.04,
      const Color(0xFF6666CC),
      const Color(0xFF333366),
    );
    _ring(
      'l-80',
      _R * 0.174,
      -_R * 0.985,
      0.04,
      const Color(0xFF6666CC),
      const Color(0xFF333366),
    );

    // ─── MERIDIANS — 6 great circles (every 30°), 10 segs each ───
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

    // ─── AXES — thin beams ───
    _beam(
      'aX',
      const Color(0xFFFF4444),
      const Color(0xFFAA2222),
      Vector3(_R * 2, 0.15, 0.15),
    );
    _beam(
      'aY',
      const Color(0xFFCCCCFF),
      const Color(0xFF7777AA),
      Vector3(0.15, _R * 2, 0.15),
    );
    _beam(
      'aZ',
      const Color(0xFF4466FF),
      const Color(0xFF2233AA),
      Vector3(0.15, 0.15, _R * 2),
    );

    // ─── CARDINAL SPHERES — glow markers ───
    _card('N', const Color(0xFFFF3333), Vector3(0, 0, -_R), 2.5);
    _card('S', const Color(0xFFFFAA00), Vector3(0, 0, _R), 2.0);
    _card('E', const Color(0xFF00EEFF), Vector3(_R, 0, 0), 2.0);
    _card('W', const Color(0xFFFF55FF), Vector3(-_R, 0, 0), 2.0);
    // Poles — SMALL circles (not giant)
    _card('Up', const Color(0xFFFFFFFF), Vector3(0, _R, 0), 1.2);
    _card('Dn', const Color(0xFF888888), Vector3(0, -_R, 0), 0.8);

    // ─── CARDINAL TEXT LABELS (SpatialText billboards) ───
    _label('tN', 'NORTH', Vector3(0, 2, -_R + 5), 3.5, const Color(0xFFFF4444));
    _label('tS', 'SOUTH', Vector3(0, 2, _R - 5), 3.0, const Color(0xFFFFAA00));
    _label('tE', 'EAST', Vector3(_R - 5, 2, 0), 3.0, const Color(0xFF00EEFF));
    _label('tW', 'WEST', Vector3(-_R + 5, 2, 0), 3.0, const Color(0xFFFF55FF));
    _label('tU', 'ZENITH', Vector3(0, _R - 5, 0), 2.5, const Color(0xFFFFFFFF));
    _label('tD', 'NADIR', Vector3(0, -_R + 5, 0), 2.0, const Color(0xFF888888));

    // ─── LATITUDE LABELS ───
    _label(
      't30',
      '30\u00b0N',
      Vector3(_R * 0.866 + 2, _R * 0.5, 0),
      2.0,
      const Color(0xFF00CCFF),
    );
    _label(
      't-30',
      '30\u00b0S',
      Vector3(_R * 0.866 + 2, -_R * 0.5, 0),
      2.0,
      const Color(0xFF00CCFF),
    );
    _label(
      't60',
      '60\u00b0N',
      Vector3(_R * 0.5 + 2, _R * 0.866, 0),
      1.8,
      const Color(0xFF0088DD),
    );
    _label(
      't-60',
      '60\u00b0S',
      Vector3(_R * 0.5 + 2, -_R * 0.866, 0),
      1.8,
      const Color(0xFF0088DD),
    );
    _label(
      'tEq',
      'EQUATOR',
      Vector3(_R + 3, 2, 0),
      2.5,
      const Color(0xFFFFDD00),
    );

    // ─── GROUND ───
    engine.scene.add(
      LitMeshNode(
          name: 'gnd',
          geometry: PlaneGeometry(width: 120, height: 120),
          material: VRMaterial(color: const Color(0xFF060610)),
        )
        ..transform.position = Vector3(0, -1.6, 0)
        ..onTransformChanged(),
    );

    // ─── LIGHTS — mostly emissive scene ───
    engine.scene.add(Light.ambient(intensity: 0.5));
    engine.scene.add(
      Light.directional(direction: Vector3(-0.3, -1, -0.5), intensity: 0.35),
    );
  }

  void _ring(String n, double r, double y, double h, Color c, Color e) {
    engine.scene.add(
      LitMeshNode(
          name: n,
          geometry: CylinderGeometry(radius: r, height: h, segments: 36),
          material: VRMaterial(color: c, emissive: e, metallic: 0.5),
        )
        ..transform.position = Vector3(0, y, 0)
        ..onTransformChanged(),
    );
  }

  void _meridianSeg(
    String n,
    double lon,
    double a1,
    double a2,
    Color c,
    Color e,
    double thick,
  ) {
    final p1 = Vector3(
      _R * cos(a1) * sin(lon),
      _R * sin(a1),
      _R * cos(a1) * cos(lon),
    );
    final p2 = Vector3(
      _R * cos(a2) * sin(lon),
      _R * sin(a2),
      _R * cos(a2) * cos(lon),
    );
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
  }

  void _beam(String n, Color c, Color e, Vector3 s) {
    engine.scene.add(
      LitMeshNode(
          name: n,
          geometry: CubeGeometry(size: 1),
          material: VRMaterial(color: c, emissive: e),
        )
        ..transform.scale = s
        ..onTransformChanged(),
    );
  }

  void _card(String n, Color c, Vector3 p, double sz) {
    engine.scene.add(
      LitMeshNode(
          name: 'c$n',
          geometry: SphereGeometry(radius: sz, segments: 8),
          material: VRMaterial(
            color: c,
            emissive: Color.fromARGB(
              120,
              (c.r * 255).round(),
              (c.g * 255).round(),
              (c.b * 255).round(),
            ),
            metallic: 0.7,
          ),
        )
        ..transform.position = p
        ..onTransformChanged(),
    );
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

  // ─── Animation — zone detection + cardinal pulse ───

  void _animate(double dt) {
    // Zone detection
    _zone = _ZoneDetector.detect(engine.cameraRig.headTransform.forward);

    final t = engine.frameCount * 0.016;

    // Pulse cardinals
    for (final l in ['cN', 'cS', 'cE', 'cW', 'cUp', 'cDn']) {
      final n = engine.scene.root.findChild(l);
      if (n != null) {
        n.transform.scale = Vector3.all(
          1.0 + sin(t * 1.5 + n.hashCode.toDouble()) * 0.06,
        );
        n.onTransformChanged();
      }
    }

    // Billboard texts auto-rotate in onUpdate() via Billboard base class
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _ticker.dispose();
    engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: CustomPaint(painter: _P(engine, _repaint), size: Size.infinite),
      ),
    );
  }
}

class _P extends CustomPainter {
  final VREngine e;
  _P(this.e, _Notifier n) : super(repaint: n);
  @override
  void paint(Canvas c, Size s) {
    if (!s.isEmpty) e.renderPass.renderStereo(c, s);
  }

  @override
  bool shouldRepaint(_P o) => true;
}

class _Notifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
