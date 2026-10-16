import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'engine adapter borrows by default and owned close is idempotent',
    () async {
      final borrowed = _Engine();
      final session = VrSessionController(
        adapter: VREngineSessionAdapter(engine: borrowed),
      );
      await session.start();
      await session.pause();
      await session.resume();
      await session.closeSession();
      expect(borrowed.isRunning, isFalse);
      expect(borrowed.disposes, 0);
      borrowed.dispose();
      final owned = _Engine();
      final adapter = VREngineSessionAdapter(engine: owned, ownsEngine: true);
      adapter.close();
      adapter.close();
      expect(owned.disposes, 1);
    },
  );
}

class _Engine extends VREngine {
  int disposes = 0;
  bool running = false;
  @override
  bool get isRunning => running;
  @override
  void start() => running = true;
  @override
  void stop() => running = false;
  @override
  void dispose() {
    disposes++;
    super.dispose();
  }
}
