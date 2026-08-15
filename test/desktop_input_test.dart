import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

KeyDownEvent _keyDown(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyW,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

KeyUpEvent _keyUp(LogicalKeyboardKey key) => KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.keyW,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

void main() {
  group('DesktopInputDriver', () {
    late CameraRig rig;
    late DesktopInputDriver driver;

    setUp(() {
      rig = CameraRig();
      rig.position = Vector3(0, 1.6, 5);
      driver = DesktopInputDriver(cameraRig: rig);
    });

    test('mouse drag rotates camera (grab-the-world convention)', () {
      final before = rig.headTransform.forward.clone();

      // Drag 100px to the right -> yaw -0.35 rad (same sign as touch fallback)
      driver.handlePointerDelta(const Offset(100, 0));

      final expected =
          Quaternion.euler(-100 * 0.0035, 0, 0).rotated(Vector3(0, 0, -1));
      final fwd = rig.headTransform.forward;
      expect(fwd.x, closeTo(expected.x, 1e-6));
      expect(fwd.y, closeTo(expected.y, 1e-6));
      expect(fwd.z, closeTo(expected.z, 1e-6));
      expect(fwd.distanceTo(before), greaterThan(0.1));
    });

    test('vertical drag pitches the camera', () {
      driver.handlePointerDelta(const Offset(0, 50));
      final fwd = rig.headTransform.forward;
      expect(fwd.y, greaterThan(0.1)); // drag down -> look up (grab world)
    });

    test('invertY flips vertical look direction', () {
      driver.invertY = true;
      driver.handlePointerDelta(const Offset(0, 50));
      expect(rig.headTransform.forward.y, lessThan(-0.1));
    });

    test('disabled driver ignores input', () {
      driver.enabled = false;
      driver.handlePointerDelta(const Offset(100, 100));
      expect(rig.headTransform.forward.z, closeTo(-1, 1e-6));

      expect(driver.handleKeyEvent(_keyDown(LogicalKeyboardKey.keyW)), isFalse);
      driver.update(1.0);
      expect(rig.position.z, closeTo(5, 1e-6));
    });

    test('WASD moves camera forward relative to yaw', () {
      driver.handleKeyEvent(_keyDown(LogicalKeyboardKey.keyW));
      driver.update(1.0); // 1 second at 3.0 m/s

      // Default camera looks toward -Z
      expect(rig.position.z, closeTo(5 - 3.0, 1e-6));
      expect(rig.position.x, closeTo(0, 1e-6));
      expect(rig.position.y, closeTo(1.6, 1e-6)); // no vertical drift
    });

    test('strafe right moves along camera right vector', () {
      driver.handleKeyEvent(_keyDown(LogicalKeyboardKey.keyD));
      driver.update(1.0);
      expect(rig.position.x, closeTo(3.0, 1e-6));
    });

    test('sprint multiplies speed', () {
      driver.handleKeyEvent(_keyDown(LogicalKeyboardKey.keyW));
      driver.handleKeyEvent(_keyDown(LogicalKeyboardKey.shiftLeft));
      driver.update(1.0);
      expect(rig.position.z, closeTo(5 - 3.0 * 2.5, 1e-6));
    });

    test('movement stops after key release', () {
      driver.handleKeyEvent(_keyDown(LogicalKeyboardKey.keyW));
      driver.handleKeyEvent(_keyUp(LogicalKeyboardKey.keyW));
      driver.update(1.0);
      expect(rig.position.z, closeTo(5, 1e-6));
    });

    test('releaseAllKeys stops movement (window focus loss)', () {
      driver.handleKeyEvent(_keyDown(LogicalKeyboardKey.keyW));
      driver.releaseAllKeys();
      driver.update(1.0);
      expect(rig.position.z, closeTo(5, 1e-6));
    });

    test('unmanaged keys are ignored by the handler', () {
      final handled = driver.handleKeyEvent(_keyDown(LogicalKeyboardKey.keyP));
      expect(handled, isFalse);
      expect(driver.pressedKeys, isEmpty);
    });

    test('screenPointToRay at viewport center matches camera forward', () {
      const size = Size(800, 600);
      final ray = driver.screenPointToRay(const Offset(400, 300), size);
      final fwd = rig.headTransform.forward;
      expect(ray.direction.x, closeTo(fwd.x, 1e-3));
      expect(ray.direction.y, closeTo(fwd.y, 1e-3));
      expect(ray.direction.z, closeTo(fwd.z, 1e-3));
    });

    test('screenPointToRay off-center deviates from forward', () {
      const size = Size(800, 600);
      final center = driver.screenPointToRay(const Offset(400, 300), size);
      final edge = driver.screenPointToRay(const Offset(790, 300), size);
      expect(edge.direction.distanceTo(center.direction), greaterThan(0.1));
    });

    test('pick hits a node under the cursor', () {
      final scene = Scene();
      final cube = LitMeshNode(
        name: 'target',
        geometry: CubeGeometry(size: 1),
        material: VRMaterial(),
      );
      cube.transform.position = Vector3(0, 1.6, 0); // in front of camera
      cube.onTransformChanged();
      scene.add(cube);

      const size = Size(800, 600);
      final hit = driver.pick(const Offset(400, 300), size, scene.root);
      expect(hit, isNotNull);
      expect(hit!.node.name, equals('target'));
    });

    test('pick returns null when nothing is under the cursor', () {
      final scene = Scene();
      final cube = LitMeshNode(
        name: 'target',
        geometry: CubeGeometry(size: 1),
        material: VRMaterial(),
      );
      cube.transform.position = Vector3(0, 1.6, 0);
      cube.onTransformChanged();
      scene.add(cube);

      const size = Size(800, 600);
      // Far corner of the viewport — misses the cube
      final hit = driver.pick(const Offset(5, 5), size, scene.root);
      expect(hit, isNull);
    });
  });

  group('VREngine desktop integration', () {
    test('enableDesktopInput creates driver bound to cameraRig', () {
      final engine = VREngine();
      final driver = engine.enableDesktopInput(moveSpeed: 5.0);
      expect(engine.desktopInput, same(driver));
      expect(driver.moveSpeed, 5.0);

      engine.disableDesktopInput();
      expect(engine.desktopInput, isNull);
      engine.dispose();
    });
  });
}
