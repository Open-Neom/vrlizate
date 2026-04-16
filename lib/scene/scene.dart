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

  Scene({
    this.backgroundColor = const Color(0xFF0A0A1A),
    this.ambientColor = const Color(0xFF202030),
    this.fogDensity = 0,
    this.fogColor = const Color(0xFF000000),
  });

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
