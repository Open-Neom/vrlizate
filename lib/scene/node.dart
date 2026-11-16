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
  Aabb? _worldAabbCache;
  bool _worldAabbDirty = true;

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
      // The child no longer contributes to this subtree's union AABB
      _markAabbDirtyUp();
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
    _markAabbDirtyUp();
    for (final child in _children) {
      child._markWorldDirty();
    }
  }

  /// A transform change anywhere in the subtree invalidates the union AABBs
  /// of all ancestors (their boxes must contain this node).
  void _markAabbDirtyUp() {
    _worldAabbDirty = true;
    var p = _parent;
    while (p != null) {
      p._worldAabbDirty = true;
      p = p._parent;
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

  static bool _isStandardFiniteMatrix(Matrix4 m) {
    if (m.runtimeType != Matrix4) return false;
    final s = m.storage;
    return (s[0] +
            s[1] +
            s[2] +
            s[4] +
            s[5] +
            s[6] +
            s[8] +
            s[9] +
            s[10] +
            s[12] +
            s[13] +
            s[14])
        .isFinite;
  }

  /// Computes the AABB of this node's own geometry in world space
  /// (without descendants). Used for self-hits in raycasting and physics.
  Aabb get ownWorldAabb {
    final local = localAabb;
    final m = worldMatrix;
    if (_isStandardFiniteMatrix(m)) {
      final out = Aabb();
      local.transformAffineInto(m, out);
      return out;
    }
    return local.transformed(m);
  }

  /// Computes the AABB of this node AND all its descendants in world space.
  /// Group nodes have no geometry, so their own box would be a phantom ±0.5m
  /// cube at their position — using it for culling wrongly discarded entire
  /// subtrees. The union is cached and invalidated on any transform or
  /// hierarchy change in the subtree.
  Aabb get worldAabb {
    if (_worldAabbDirty || _worldAabbCache == null) {
      final m = worldMatrix;
      if (_isStandardFiniteMatrix(m)) {
        final cache = _worldAabbCache ??= Aabb();
        localAabb.transformAffineInto(m, cache);
        for (var i = 0; i < _children.length; i++) {
          cache.expandBoundsInPlace(_children[i].worldAabb);
        }
      } else {
        final result = localAabb.transformed(m);
        for (final child in _children) {
          result.expandToIncludeAabb(child.worldAabb);
        }
        _worldAabbCache = result;
      }
      _worldAabbDirty = false;
    }
    return _worldAabbCache!;
  }

  /// Override to provide local-space bounding box.
  Aabb get localAabb =>
      Aabb.fromCenterExtents(Vector3.zero(), Vector3(0.5, 0.5, 0.5));

  /// Whether this node contributes pixels during a render pass.
  ///
  /// Container nodes remain non-renderable while meshes and spatial UI
  /// surfaces opt in. This keeps scene grouping nodes out of draw sorting.
  bool get isRenderable => false;

  /// Whether this node requires back-to-front alpha ordering.
  bool get isTransparent => false;

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
