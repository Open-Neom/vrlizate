import 'dart:math';

class Offset3D {
  final double x;
  final double y;
  final double z;

  const Offset3D(this.x, this.y, this.z);

  Offset3D operator +(Offset3D other) =>
      Offset3D(x + other.x, y + other.y, z + other.z);
  Offset3D operator -(Offset3D other) =>
      Offset3D(x - other.x, y - other.y, z - other.z);
  Offset3D operator *(double s) => Offset3D(x * s, y * s, z * s);

  double get length => sqrt(x * x + y * y + z * z);
  Offset3D get normalized {
    final l = length;
    return l > 0 ? Offset3D(x / l, y / l, z / l) : const Offset3D(0, 0, 0);
  }

  double dot(Offset3D other) => x * other.x + y * other.y + z * other.z;

  Offset3D cross(Offset3D other) => Offset3D(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  /// Converts spherical coordinates (theta, phi, radius) to cartesian.
  static Offset3D fromSpherical(double theta, double phi, double radius) {
    return Offset3D(
      radius * cos(phi) * cos(theta),
      radius * cos(phi) * sin(theta),
      radius * sin(phi),
    );
  }

  /// Rotates this point around Y axis (horizontal camera rotation).
  Offset3D rotateY(double angle) {
    final c = cos(angle);
    final s = sin(angle);
    return Offset3D(x * c + z * s, y, -x * s + z * c);
  }

  /// Rotates this point around X axis (vertical camera rotation).
  Offset3D rotateX(double angle) {
    final c = cos(angle);
    final s = sin(angle);
    return Offset3D(x, y * c - z * s, y * s + z * c);
  }

  @override
  String toString() => 'Offset3D($x, $y, $z)';
}
