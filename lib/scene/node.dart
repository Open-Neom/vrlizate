import 'dart:ui';

import 'package:vector_math/vector_math.dart';
import '../interaction/pointable.dart';

import '../core/math/aabb.dart';
import '../core/math/transform3d.dart';

/// Base node in the scene graph with parent-child hierarchy.
/// All spatial objects inherit from Node.
class Node {
  String name;
  final Transform3D transform;
  Node? _parent;
  final List<Node> _children = [];
  bool visible = true;
  Pointable? pointable;

  Matrix4? _worldMatrix;
  bool _worldDirty = true;

  Node({this.name = '', Transform3D? transform})
    : transform = transform ?? Transform3D();

  // ─── Hierarchy ──────────────────────

  Node? get parent => _parent;
  List<Node> get children => List.unmodifiable(_children);
  int get childCount => _children.length;

  void addChild(Node child) {
    child._parent?._children.remove(child);
    child._parent = this;
    _children.add(child);
    child._markWorldDirty();
  }

  void removeChild(Node child) {
    if (_children.remove(child)) {
      child._parent = null;
      child._markWorldDirty();
    }
  }

  void removeFromParent() {
    _parent?.removeChild(this);
  }

  /// Finds a child by name recursively.
  Node? findChild(String name) {
    for (final child in _children) {
      if (child.name == name) return child;
      final found = child.findChild(name);
      if (found != null) return found;
    }
    return null;
  }

  // ─── Transforms ──────────────────────

  /// Local transform matrix.
  Matrix4 get localMatrix => transform.localMatrix;

  /// World transform matrix (accumulated from root).
  Matrix4 get worldMatrix {
    if (_worldDirty || _worldMatrix == null) {
      if (_parent != null) {
        _worldMatrix = _parent!.worldMatrix * localMatrix;
      } else {
        _worldMatrix = localMatrix.clone();
      }
      _worldDirty = false;
    }
    return _worldMatrix!;
  }

  /// World position extracted from world matrix.
  Vector3 get worldPosition => worldMatrix.getTranslation();

  void _markWorldDirty() {
    _worldDirty = true;
    _worldMatrix = null;
    for (final child in _children) {
      child._markWorldDirty();
    }
  }

  /// Called when any transform property changes.
  void onTransformChanged() {
    _markWorldDirty();
  }

  // ─── Lifecycle ──────────────────────

  /// Called once per frame before rendering.
  void update(double dt) {
    if (!visible) return;
    onUpdate(dt);
    for (final child in _children) {
      child.update(dt);
    }
  }

  /// Override for custom per-frame logic.
  void onUpdate(double dt) {}

  /// Renders this node and children to the canvas.
  void render(Canvas canvas, Matrix4 viewProjection) {
    if (!visible) return;
    onRender(canvas, viewProjection);
    for (final child in _children) {
      child.render(canvas, viewProjection);
    }
  }

  /// Override for custom rendering.
  void onRender(Canvas canvas, Matrix4 viewProjection) {}

  /// Computes the AABB of this node in world space.
  Aabb get worldAabb {
    final local = localAabb;
    return local.transformed(worldMatrix);
  }

  /// Override to provide local-space bounding box.
  Aabb get localAabb =>
      Aabb.fromCenterExtents(Vector3.zero(), Vector3(0.5, 0.5, 0.5));

  // ─── Traversal ──────────────────────

  /// Traverses the tree depth-first, calling visitor for each node.
  void traverse(void Function(Node node) visitor) {
    visitor(this);
    for (final child in _children) {
      child.traverse(visitor);
    }
  }

  /// Collects all visible nodes in the tree.
  List<Node> collectVisible() {
    final result = <Node>[];
    traverse((node) {
      if (node.visible) result.add(node);
    });
    return result;
  }

  @override
  String toString() => 'Node($name, children: $childCount)';
}
