import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GazePointer adaptive dwell', () {
    // Note: the first update() that enters a target only registers the
    // target change; the dwell timer accumulates from the next update on.

    test('dwell selects after dwellDuration', () {
      final pointer = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 1.0,
        adaptiveDwell: false,
      );
      String? selected;
      pointer.onDwellSelect = (id) => selected = id;

      pointer.update(0.01, 'node-a'); // Enter.
      pointer.update(0.5, 'node-a');
      expect(selected, isNull);
      expect(pointer.dwellProgress, closeTo(0.5, 1e-9));

      pointer.update(0.6, 'node-a');
      expect(selected, 'node-a');
      expect(pointer.dwellProgress, 1.0);
    });

    test('adaptive dwell accelerates repeated selections of same target', () {
      final pointer = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 1.0,
        minDwellDuration: 0.5,
        dwellAcceleration: 0.8,
      );

      void select(String id, double dwellFor) {
        pointer.update(0.01, id); // Enter.
        pointer.update(dwellFor, id); // Dwell to selection.
        pointer.update(0.3, null); // Exit beyond grace (0.15 default).
      }

      select('a', 1.1); // 1st selection: resets to full duration.
      expect(pointer.effectiveDwellDuration, 1.0);

      select('a', 1.1); // 2nd consecutive: 1.0 * 0.8.
      expect(pointer.effectiveDwellDuration, closeTo(0.8, 1e-9));

      select('a', 0.9); // 3rd: 0.8 * 0.8.
      expect(pointer.effectiveDwellDuration, closeTo(0.64, 1e-9));

      select('b', 1.1); // Different target: resets adaptation.
      expect(pointer.effectiveDwellDuration, 1.0);
    });

    test('adaptive dwell is clamped at minDwellDuration', () {
      final pointer = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 1.0,
        minDwellDuration: 0.5,
        dwellAcceleration: 0.5,
      );

      for (var i = 0; i < 5; i++) {
        pointer.update(0.01, 'a');
        pointer.update(1.1, 'a');
        pointer.update(0.3, null);
      }
      // 1.0 -> 0.5 -> clamped at 0.5 from then on.
      expect(pointer.effectiveDwellDuration, 0.5);
    });

    test('grace period preserves dwell across brief gaze slips', () {
      final pointer = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 1.0,
        gazeGracePeriod: 0.2,
        adaptiveDwell: false,
      );
      String? selected;
      pointer.onDwellSelect = (id) => selected = id;

      pointer.update(0.01, 'node-a'); // Enter.
      pointer.update(0.5, 'node-a');
      expect(pointer.dwellProgress, closeTo(0.5, 1e-9));

      // Brief slip (within grace): progress holds.
      pointer.update(0.1, null);
      expect(pointer.gazeTargetId, 'node-a');
      expect(pointer.dwellProgress, closeTo(0.5, 1e-9));

      // Gaze returns within the grace window: timer resumes.
      pointer.update(0.0, 'node-a');
      expect(pointer.dwellProgress, closeTo(0.5, 1e-9));

      pointer.update(0.6, 'node-a');
      expect(selected, 'node-a');
    });

    test('slip longer than grace resets the dwell timer', () {
      final pointer = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 1.0,
        gazeGracePeriod: 0.1,
        adaptiveDwell: false,
      );
      String? selected;
      pointer.onDwellSelect = (id) => selected = id;

      pointer.update(0.01, 'node-a');
      pointer.update(0.5, 'node-a');
      pointer.update(0.2, null); // Exceeds grace period.
      expect(pointer.gazeTargetId, isNull);
      expect(pointer.dwellProgress, 0);

      pointer.update(0.6, 'node-a'); // Enter branch only registers the target.
      expect(selected, isNull);
      pointer.update(1.1, 'node-a'); // Full dwell again.
      expect(selected, 'node-a');
    });

    test('gaze enter/exit callbacks fire on target change', () {
      final pointer = GazePointer(cameraRig: CameraRig());
      final entered = <String>[];
      final exited = <String>[];
      pointer.onGazeEnter = entered.add;
      pointer.onGazeExit = exited.add;

      pointer.update(0.016, 'a');
      pointer.update(0.016, 'b');
      pointer.update(0.3, null); // Beyond grace.

      expect(entered, ['a', 'b']);
      expect(exited, ['a', 'b']);
    });

    test('dwell progress callback reports values in 0..1', () {
      final pointer = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 1.0,
        adaptiveDwell: false,
      );
      final progress = <double>[];
      pointer.onDwellProgress = (id, p) => progress.add(p);

      pointer.update(0.01, 'a');
      pointer.update(0.25, 'a');
      pointer.update(0.25, 'a');
      pointer.update(0.6, 'a');

      expect(progress, [closeTo(0.25, 1e-9), closeTo(0.5, 1e-9), 1.0]);
    });

    test('resetAdaptation restores the full dwell duration', () {
      final pointer = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 1.0,
        minDwellDuration: 0.4,
        dwellAcceleration: 0.5,
      );

      pointer.update(0.01, 'a');
      pointer.update(1.1, 'a');
      pointer.update(0.3, null);
      pointer.update(0.01, 'a');
      pointer.update(1.1, 'a');
      expect(pointer.effectiveDwellDuration, 0.5);

      pointer.resetAdaptation();
      expect(pointer.effectiveDwellDuration, 1.0);
    });
  });
}
