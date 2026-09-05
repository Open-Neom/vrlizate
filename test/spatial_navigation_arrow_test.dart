import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('SpatialNavigationArrow', () {
    test('builds a three-mesh arrow pointing toward the upper-left', () {
      final arrow = SpatialNavigationArrow();
      final meshes = arrow.children.whereType<MeshNode>().toList();

      expect(meshes, hasLength(3));
      expect(arrow.findChild('spatial_back_arrow_shaft'), isNotNull);

      final horizontal = arrow.findChild('spatial_back_arrow_head_horizontal');
      final vertical = arrow.findChild('spatial_back_arrow_head_vertical');
      expect(horizontal!.transform.position.x, lessThan(0));
      expect(horizontal.transform.position.y, greaterThan(0));
      expect(vertical!.transform.position.x, lessThan(0));
      expect(vertical.transform.position.y, greaterThan(0));
      expect(meshes.every((mesh) => mesh.transform.scale.z > 0), isTrue);
    });

    test('responds to hover and press as one reusable navigation target', () {
      const idle = Color(0xFF112233);
      const hover = Color(0xFF445566);
      const pressed = Color(0xFF778899);
      var pressCount = 0;
      final arrow = SpatialNavigationArrow(
        idleColor: idle,
        hoverColor: hover,
        pressColor: pressed,
        onPress: (_) => pressCount++,
      );
      final meshes = arrow.children.whereType<MeshNode>().toList();
      final pointable = arrow.pointable!;
      final hit = RaycastHit(
        node: arrow,
        point: Vector3.zero(),
        distance: 1,
        normal: Vector3(0, 0, 1),
      );

      expect(meshes.every((mesh) => mesh.material.color == idle), isTrue);
      pointable.updateHover(true);
      expect(meshes.every((mesh) => mesh.material.color == hover), isTrue);

      pointable.press(hit);
      expect(pressCount, 1);
      expect(meshes.every((mesh) => mesh.material.color == pressed), isTrue);

      pointable.release();
      expect(meshes.every((mesh) => mesh.material.color == hover), isTrue);
    });
  });
}
