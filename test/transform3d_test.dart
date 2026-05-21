import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:vrlizate/vrlizate.dart';

void main() {
  group('Transform3D', () {
    test('default identity produces identity matrix', () {
      final t = Transform3D();
      final m = t.localMatrix;

      // Should be identity
      expect(m.storage[0], closeTo(1, 1e-6));
      expect(m.storage[5], closeTo(1, 1e-6));
      expect(m.storage[10], closeTo(1, 1e-6));
      expect(m.storage[15], closeTo(1, 1e-6));
    });

    test('position applies to translation column of matrix', () {
      final t = Transform3D(position: Vector3(3, 5, -7));
      final m = t.localMatrix;

      // Translation is in column 3 (indices 12,13,14)
      expect(m.storage[12], closeTo(3, 1e-6));
      expect(m.storage[13], closeTo(5, 1e-6));
      expect(m.storage[14], closeTo(-7, 1e-6));
    });

    test('dirty flag clears after matrix access and re-sets on change', () {
      final t = Transform3D();
      t.localMatrix; // Should clear dirty
      t.position = Vector3(1, 0, 0); // Should re-set dirty

      // Verify new matrix reflects change
      final m = t.localMatrix;
      expect(m.storage[12], closeTo(1, 1e-6));
    });

    test('scale zero produces degenerate matrix but does not crash', () {
      final t = Transform3D(scale: Vector3.zero());
      final m = t.localMatrix;
      // Should not throw
      expect(m.storage[0], closeTo(0, 1e-6));
    });

    test('rotation quaternion stays normalized after multiple rotateEuler calls', () {
      final t = Transform3D();
      for (var i = 0; i < 1000; i++) {
        t.rotateEuler(0.01, 0.02, 0.005);
      }
      final length = t.rotation.length;
      expect(length, closeTo(1.0, 1e-4));
    });

    test('forward/right/up are orthogonal', () {
      final t = Transform3D();
      t.rotateEuler(0.5, 0.3, 0.1);

      final f = t.forward;
      final r = t.right;
      final u = t.up;

      // Dot products should be ~0 (orthogonal)
      expect(f.dot(r), closeTo(0, 1e-4));
      expect(f.dot(u), closeTo(0, 1e-4));
      expect(r.dot(u), closeTo(0, 1e-4));

      // Each should be unit length
      expect(f.length, closeTo(1, 1e-4));
      expect(r.length, closeTo(1, 1e-4));
      expect(u.length, closeTo(1, 1e-4));
    });

    test('lookAt produces correct forward direction', () {
      final t = Transform3D(position: Vector3(0, 0, 5));
      t.lookAt(Vector3(0, 0, 0));

      final forward = t.forward;
      // Should point toward origin (negative Z direction from pos)
      expect(forward.z, lessThan(0));
    });

    test('clone produces independent copy', () {
      final t = Transform3D(position: Vector3(1, 2, 3));
      final c = t.clone();
      c.position = Vector3(10, 20, 30);

      expect(t.position.x, closeTo(1, 1e-6));
      expect(c.position.x, closeTo(10, 1e-6));
    });

    test('reset clears all transforms', () {
      final t = Transform3D(
        position: Vector3(5, 5, 5),
        scale: Vector3(2, 2, 2),
      );
      t.rotateEuler(1, 1, 1);
      t.reset();

      expect(t.position.x, closeTo(0, 1e-6));
      expect(t.scale.x, closeTo(1, 1e-6));
      // Rotation should be identity quaternion
      expect(t.rotation.w, closeTo(1, 1e-4));
    });
  });
}
