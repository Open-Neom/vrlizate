import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'external frames advance rules once without scheduling or moving twice',
    () {
      final engine = VREngine();
      final arbiter = VrInputArbiter();
      engine.bindInput(arbiter);
      var ticks = 0;
      engine.onUpdate = (_) => ticks++;
      engine.start();
      engine.useExternalFrameDriver();
      expect(engine.isRunning, isFalse);
      arbiter.emit(
        type: VrInputType.navigate,
        source: VrInputSource.remotePhone,
        data: {'y': 1.0},
      );
      engine.step(1 / 60, integrateInput: false);
      expect(ticks, 1);
      expect(engine.frameCount, 1);
      expect(engine.cameraRig.position, Vector3.zero());
      engine.step(double.nan);
      engine.step(0);
      expect(ticks, 1);
      engine.dispose();
      arbiter.dispose();
    },
  );

  test(
    'external renderer ray is copied and dwell can be reserved for HOME',
    () {
      final engine = VREngine();
      final ray = Ray.originDirection(Vector3(1, 2, 3), Vector3(-1, 0, 0));
      engine.setExternalInteractionRay(ray);
      ray.direction.setValues(0, 1, 0);
      expect(engine.interactionRay.direction, Vector3(-1, 0, 0));
      engine.externalDwellSuppressed = true;
      expect(engine.isDwellEnabled, isFalse);
      engine.externalDwellSuppressed = false;
      expect(engine.isDwellEnabled, isTrue);
      engine.setExternalInteractionRay(null);
      expect(engine.interactionRay.direction.z, closeTo(-1, 1e-6));
      engine.dispose();
    },
  );
}
