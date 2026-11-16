import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate/vrlizate.dart';

VrCompactGamepadFrame _frame({
  bool ready = false,
  bool zl = false,
  bool zr = false,
}) => VrCompactGamepadFrame(
  sequence: 10,
  senderTimestampMicroseconds: 20000,
  orientation: Quaternion.identity(),
  angularVelocity: Vector3.zero(),
  laserSlideActive: true,
  laserX: .25,
  pointerPoseReady: ready,
  btnL: true,
  btnR: true,
  btnZL: zl,
  btnZR: zr,
  passthroughActive: true,
  spatialHudVisible: true,
  rangeMeters: .4,
);

void main() {
  const codec = VrCompactGamepadCodec();

  test('pointer posture uses only flags8 bit3 and keeps the 46 byte ABI', () {
    final legacy = codec.encode(_frame());
    final ready = codec.encode(_frame(ready: true));
    expect(legacy, hasLength(46));
    expect(ready, hasLength(46));
    expect(legacy[42] & 0x08, 0);
    expect(ready[42] & 0x08, 0x08);
    final cleared = ready.toList()..[42] &= ~0x08;
    expect(cleared, orderedEquals(legacy));
    expect(codec.tryDecode(legacy)!.pointerPoseReady, isFalse);
    final decoded = codec.tryDecode(ready)!;
    expect(decoded.pointerPoseReady, isTrue);
    expect(decoded.passthroughActive, isTrue);
    expect(decoded.spatialHudVisible, isTrue);
    expect(decoded.rangeMeters, closeTo(.4, .001));
  });

  test('future reserved flags do not manufacture pointer posture', () {
    final data = codec.encode(_frame())..[42] |= 0xc0;
    final decoded = codec.tryDecode(data)!;
    expect(decoded.pointerPoseReady, isFalse);
    expect(decoded.laserSlideActive, isTrue);
  });

  test('ZL and ZR round-trip independently within the existing packet', () {
    final legacy = codec.encode(_frame(ready: true));
    for (final (zl, zr) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      final data = codec.encode(_frame(ready: true, zl: zl, zr: zr));
      expect(data, hasLength(46));
      final decoded = codec.tryDecode(data)!;
      expect(decoded.btnZL, zl);
      expect(decoded.btnZR, zr);
      expect(decoded.btnL, isTrue);
      expect(decoded.btnR, isTrue);
      expect(decoded.pointerPoseReady, isTrue);
      expect(data.toList()..[42] &= ~0x30, orderedEquals(legacy));
    }
  });
}
