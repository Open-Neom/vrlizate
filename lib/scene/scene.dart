import 'dart:ui';

import 'light.dart';
import 'node.dart';

/// Root of the scene graph. Contains the environment and all nodes.
class Scene {
  final Node root = Node(name: 'root');
  Color backgroundColor;
  Color ambientColor;
  double fogDensity;
  Color fogColor;

  /// Sky color straight up for a world-locked gradient sky.
  ///
  /// When this or [skyGroundColor] is set, retained GPU renderers draw a
  /// three-stop gradient dome — [skyZenithColor] overhead, [backgroundColor]
  /// at the horizon, [skyGroundColor] below — that turns with the viewer's
  /// head instead of a flat screen-space background. Leave both null for
  /// enclosed interiors: the dome is a full-screen pass drawn behind the
  /// geometry every frame, wasted where a ceiling covers it.
  Color? skyZenithColor;

  /// Color of the dome below the horizon; see [skyZenithColor].
  Color? skyGroundColor;

  /// Upper bound on fog opacity, 0..1. Below 1 distant geometry never fully
  /// dissolves, so a mountain range or skyline keeps a silhouette against
  /// the sky instead of becoming a flat wall of [fogColor].
  double fogMaxOpacity;

  /// Distance in meters past which fog is not applied (0 = no cutoff). Lets a
  /// far layer — a star field, a moon — stay crisp behind hazed terrain.
  double fogCutoffDistance;

  /// How fast fog thins with altitude above the floor (0 = uniform). Larger
  /// values hug the ground: mist over a courtyard, haze on a landing pad,
  /// clear air at head height and above. Retained GPU renderers only.
  double fogHeightFalloff;

  Scene({
    this.backgroundColor = const Color(0xFF0A0A1A),
    this.ambientColor = const Color(0xFF202030),
    this.fogDensity = 0,
    this.fogColor = const Color(0xFF000000),
    this.skyZenithColor,
    this.skyGroundColor,
    this.fogMaxOpacity = 1.0,
    this.fogCutoffDistance = 0,
    this.fogHeightFalloff = 0,
  }) : assert(fogMaxOpacity >= 0 && fogMaxOpacity <= 1),
       assert(fogCutoffDistance >= 0),
       assert(fogHeightFalloff >= 0);

  /// Whether a gradient sky dome is requested; see [skyZenithColor].
  bool get hasSkyDome => skyZenithColor != null || skyGroundColor != null;

  void add(Node node) => root.addChild(node);
  void remove(Node node) => node.removeFromParent();

  void update(double dt) => root.update(dt);

  /// Collects all lights in the scene tree.
  List<Light> get lights {
    final result = <Light>[];
    root.traverse((node) {
      if (node is Light) result.add(node);
    });
    return result;
  }

  /// Collects all visible nodes.
  List<Node> get visibleNodes => root.collectVisible();

  void clear() {
    for (final child in List.of(root.children)) {
      child.removeFromParent();
    }
  }
}
