import 'package:vector_math/vector_math.dart';

/// Full 3D transform with position, rotation (quaternion), and scale.
/// Uses dirty-flagged matrix caching for performance.
class Transform3D {
  Vector3 _position;
  Quaternion _rotation;
  Vector3 _scale;

  Matrix4? _localMatrix;
  bool _dirty = true;

  Transform3D({Vector3? position, Quaternion? rotation, Vector3? scale})
    : _position = position ?? Vector3.zero(),
      _rotation = rotation ?? Quaternion.identity(),
      _scale = scale ?? Vector3(1, 1, 1);

  Vector3 get position => _position;
  set position(Vector3 v) {
    _position = v;
    _dirty = true;
  }

  Quaternion get rotation => _rotation;
  set rotation(Quaternion q) {
    _rotation = q..normalize();
    _dirty = true;
  }

  Vector3 get scale => _scale;
  set scale(Vector3 v) {
    _scale = v;
    _dirty = true;
  }

  /// Forward direction (-Z axis in local space, rotated).
  Vector3 get forward => _rotation.rotated(Vector3(0, 0, -1));

  /// Right direction (+X axis in local space, rotated).
  Vector3 get right => _rotation.rotated(Vector3(1, 0, 0));

  /// Up direction (+Y axis in local space, rotated).
  Vector3 get up => _rotation.rotated(Vector3(0, 1, 0));

  void translate(Vector3 delta) {
    _position += delta;
    _dirty = true;
  }

  void rotate(Quaternion delta) {
    _rotation = delta * _rotation;
    _rotation.normalize();
    _dirty = true;
  }

  void rotateEuler(double yaw, double pitch, double roll) {
    final q = Quaternion.euler(yaw, pitch, roll);
    rotate(q);
  }

  void lookAt(Vector3 target, {Vector3? up}) {
    final upDir = up ?? Vector3(0, 1, 0);

    final m = makeViewMatrix(_position, target, upDir);
    _rotation = Quaternion.fromRotation(m.getRotation()..transpose());
    _rotation.normalize();
    _dirty = true;
  }

  /// Returns the local transform matrix (TRS).
  Matrix4 get localMatrix {
    if (_dirty || _localMatrix == null) {
      _localMatrix = Matrix4.compose(_position, _rotation, _scale);
      _dirty = false;
    }
    return _localMatrix!;
  }

  /// Resets to identity.
  void reset() {
    _position = Vector3.zero();
    _rotation = Quaternion.identity();
    _scale = Vector3(1, 1, 1);
    _dirty = true;
  }

  Transform3D clone() => Transform3D(
    position: _position.clone(),
    rotation: _rotation.clone(),
    scale: _scale.clone(),
  );
}
