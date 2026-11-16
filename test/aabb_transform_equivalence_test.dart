import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' as vr;

// Literal BEFORE constructor/expand/transformed oracle, reviewed against the
// complete original aabb.dart SHA-256 below. No external path or fixture is
// required when this test is included in the public source SDK ZIP.
const _beforeSha256 =
    'fdf4eba1de1af308d86c0493a9228ef769854eddafa0883997392d7a7787152b';

List<int> _bits(Float32List data) => Uint32List.view(
  data.buffer,
  data.offsetInBytes,
  data.length,
).toList(growable: false);

Float32List _copyStorage(Float32List data) {
  final result = Float32List(data.length);
  Uint32List.view(result.buffer).setAll(0, _bits(data));
  return result;
}

vm.Vector3 _copyVector(vm.Vector3 value) =>
    vm.Vector3.fromFloat32List(_copyStorage(value.storage));

vm.Vector3 _fromWords(List<int> words) {
  final values = Float32List(3);
  Uint32List.view(values.buffer).setAll(0, words);
  return vm.Vector3.fromFloat32List(values);
}

vm.Matrix4 _matrixFromWords(List<int> words) {
  final values = Float32List(16);
  Uint32List.view(values.buffer).setAll(0, words);
  return vm.Matrix4.fromFloat32List(values);
}

List<List<int>> _boundBits(vm.Vector3 min, vm.Vector3 max) => [
  _bits(min.storage),
  _bits(max.storage),
];

class _RecordingMatrix extends vm.Matrix4 {
  _RecordingMatrix(vm.Matrix4 source) : super.zero() {
    Uint32List.view(storage.buffer).setAll(0, _bits(source.storage));
  }

  final arguments = <vm.Vector3>[];
  final argumentBits = <List<int>>[];
  final outputs = <vm.Vector3>[];
  final outputBits = <List<int>>[];
  final outParameters = <vm.Vector3?>[];

  @override
  vm.Vector3 transformed3(vm.Vector3 arg, [vm.Vector3? out]) {
    arguments.add(arg);
    argumentBits.add(_bits(arg.storage));
    outParameters.add(out);
    final result = super.transformed3(arg, out);
    outputs.add(result);
    outputBits.add(_bits(result.storage));
    return result;
  }
}

class _SequenceMatrix extends vm.Matrix4 {
  _SequenceMatrix(List<vm.Vector3> values, {this.reuseOutput = false})
    : values = [for (final value in values) _copyVector(value)],
      super.zero();

  final List<vm.Vector3> values;
  final bool reuseOutput;
  final sharedOutput = vm.Vector3.zero();
  final argumentBits = <List<int>>[];
  final arguments = <vm.Vector3>[];
  final outputs = <vm.Vector3>[];
  var calls = 0;

  @override
  vm.Vector3 transformed3(vm.Vector3 arg, [vm.Vector3? out]) {
    expect(out, isNull);
    arguments.add(arg);
    argumentBits.add(_bits(arg.storage));
    final value = values[calls++];
    if (reuseOutput) {
      Uint32List.view(
        sharedOutput.storage.buffer,
      ).setAll(0, _bits(value.storage));
      outputs.add(sharedOutput);
      return sharedOutput;
    }
    outputs.add(value);
    return value;
  }
}

void _equivalent(
  String label,
  vm.Vector3 low,
  vm.Vector3 high,
  vm.Matrix4 matrix,
) {
  final actual = vr.Aabb(min: _copyVector(low), max: _copyVector(high));
  final before = _BeforeAabb(min: _copyVector(low), max: _copyVector(high));
  final actualMatrix = _RecordingMatrix(matrix);
  final beforeMatrix = _RecordingMatrix(matrix);
  final inputBits = _boundBits(actual.min, actual.max);
  final matrixBits = _bits(actualMatrix.storage);
  final result = actual.transformed(actualMatrix);
  final expected = before.transformed(beforeMatrix);
  final reason = '$label; literal BEFORE $_beforeSha256';

  expect(
    _boundBits(result.min, result.max),
    _boundBits(expected.min, expected.max),
    reason: reason,
  );
  expect(_boundBits(actual.min, actual.max), inputBits, reason: reason);
  expect(_boundBits(before.min, before.max), inputBits, reason: reason);
  expect(_bits(actualMatrix.storage), matrixBits, reason: reason);
  expect(_bits(beforeMatrix.storage), matrixBits, reason: reason);
  expect(actualMatrix.arguments, hasLength(8), reason: reason);
  expect(beforeMatrix.arguments, hasLength(8), reason: reason);
  expect(actualMatrix.argumentBits, beforeMatrix.argumentBits, reason: reason);
  expect(actualMatrix.outParameters, everyElement(isNull), reason: reason);
  expect(actualMatrix.outputBits, [
    for (final value in actualMatrix.outputs) _bits(value.storage),
  ], reason: 'Accumulator must not mutate matrix output vectors: $reason');
  for (final input in [actual.min, actual.max, ...actualMatrix.outputs]) {
    expect(identical(result.min, input), isFalse, reason: reason);
    expect(identical(result.max, input), isFalse, reason: reason);
  }
  expect(identical(result.min, result.max), isFalse, reason: reason);
}

void main() {
  test(
    'Aabb transform preserves Float32 bits for named matrices and boxes',
    () {
      final matrices = <String, vm.Matrix4>{
        'identity': vm.Matrix4.identity(),
        'translation': vm.Matrix4.translationValues(1.5, -2.25, 3.875),
        'rotation': vm.Matrix4.rotationZ(math.pi / 7)
          ..multiply(vm.Matrix4.rotationX(-.73))
          ..multiply(vm.Matrix4.rotationY(.21)),
        'negative scale': vm.Matrix4.diagonal3Values(-2, 3, -.5),
        'shear': vm.Matrix4.identity()
          ..setEntry(0, 1, 1.25)
          ..setEntry(1, 2, -.5)
          ..setEntry(2, 0, .375),
        'singular': vm.Matrix4.diagonal3Values(1, 0, -2),
        'zero': vm.Matrix4.zero(),
        'perspective row': vm.Matrix4.identity()
          ..setEntry(3, 0, .25)
          ..setEntry(3, 1, -.5)
          ..setEntry(3, 2, .75)
          ..setEntry(3, 3, 2),
        'infinity': vm.Matrix4.identity()..setEntry(0, 0, double.infinity),
        'NaN payload': _matrixFromWords([
          0x3f800000,
          0,
          0,
          0,
          0,
          0x7fc01234,
          0,
          0,
          0,
          0,
          0x3f800000,
          0,
          0,
          0,
          0,
          0x3f800000,
        ]),
      };
      final empty = vr.Aabb();
      final boxes = <String, (vm.Vector3, vm.Vector3)>{
        'ordinary': (vm.Vector3(-2, -3, -4), vm.Vector3(5, 6, 7)),
        'empty default': (empty.min, empty.max),
        'inverted': (vm.Vector3(5, 6, 7), vm.Vector3(-2, -3, -4)),
        'partly inverted': (vm.Vector3(3, -4, 2), vm.Vector3(-2, 5, 2)),
        'point': (vm.Vector3(1, 2, 3), vm.Vector3(1, 2, 3)),
        'signed zero': (
          _fromWords([0x80000000, 0, 0x80000000]),
          _fromWords([0, 0x80000000, 0]),
        ),
        'subnormal/extreme': (
          _fromWords([1, 0x807fffff, 0xff7fffff]),
          _fromWords([0x7f7fffff, 0x00800000, 0x80000001]),
        ),
        'infinite': (
          vm.Vector3(double.negativeInfinity, -1, 0),
          vm.Vector3(double.infinity, 1, 4),
        ),
        'NaN payloads': (
          _fromWords([0x7fc01234, 0x80000000, 0x3f800000]),
          _fromWords([0x40000000, 0xffc05678, 0x7fc12345]),
        ),
      };
      for (final box in boxes.entries) {
        for (final matrix in matrices.entries) {
          _equivalent(
            '${box.key}/${matrix.key}',
            box.value.$1,
            box.value.$2,
            matrix.value,
          );
        }
      }
    },
  );

  test(
    'Aabb dispatches exactly eight distinct corners in the original order',
    () {
      final matrix = _RecordingMatrix(vm.Matrix4.identity());
      final box = vr.Aabb(
        min: vm.Vector3(-2, -3, -4),
        max: vm.Vector3(5, 6, 7),
      );
      box.transformed(matrix);
      final corners = [
        [-2.0, -3.0, -4.0],
        [5.0, -3.0, -4.0],
        [-2.0, 6.0, -4.0],
        [5.0, 6.0, -4.0],
        [-2.0, -3.0, 7.0],
        [5.0, -3.0, 7.0],
        [-2.0, 6.0, 7.0],
        [5.0, 6.0, 7.0],
      ];
      expect(matrix.argumentBits, [
        for (final point in corners) _bits(vm.Vector3.array(point).storage),
      ]);
      expect(matrix.arguments, hasLength(8));
      for (var i = 0; i < matrix.arguments.length; i++) {
        for (var j = 0; j < i; j++) {
          expect(identical(matrix.arguments[i], matrix.arguments[j]), isFalse);
        }
      }
    },
  );

  test(
    'Aabb retains the legacy no-perspective-divide transform3 semantics',
    () {
      final low = vm.Vector3(-2, -3, -4), high = vm.Vector3(5, 6, 7);
      final matrix = vm.Matrix4.identity()
        ..setEntry(3, 0, .25)
        ..setEntry(3, 1, -.5)
        ..setEntry(3, 2, .75)
        ..setEntry(3, 3, 2);
      final result = vr.Aabb(min: low, max: high).transformed(matrix);
      expect(_boundBits(result.min, result.max), _boundBits(low, high));
    },
  );

  test(
    'strict comparisons preserve first signed-zero ties through dispatch',
    () {
      final first = _fromWords([0x80000000, 0, 0x80000000]);
      final other = _fromWords([0, 0x80000000, 0]);
      final sequence = [first, for (var i = 0; i < 7; i++) other];
      final actualMatrix = _SequenceMatrix(sequence);
      final beforeMatrix = _SequenceMatrix(sequence);
      final box = vr.Aabb(
        min: vm.Vector3(-1, -2, -3),
        max: vm.Vector3(4, 5, 6),
      );
      final result = box.transformed(actualMatrix);
      final expected = _BeforeAabb(
        min: box.min,
        max: box.max,
      ).transformed(beforeMatrix);
      expect(actualMatrix.calls, 8);
      expect(actualMatrix.argumentBits, beforeMatrix.argumentBits);
      expect(_bits(result.min.storage), _bits(first.storage));
      expect(_bits(result.max.storage), _bits(first.storage));
      expect(
        _boundBits(result.min, result.max),
        _boundBits(expected.min, expected.max),
      );
    },
  );

  test(
    'scripted NaN payloads, infinities and reused output vectors stay equivalent',
    () {
      final sequence = [
        _fromWords([0x80000000, 0, 0x7f800000]),
        _fromWords([0, 0x80000000, 0xff800000]),
        _fromWords([0x7fc01234, 0x40a00000, 0xffc05678]),
        _fromWords([0x7f800000, 0xc0e00000, 0x80000000]),
        _fromWords([0xff800000, 0x7f800000, 0]),
        _fromWords([0xffc12345, 0xff800000, 0x3f800000]),
        _fromWords([0x40400000, 0x7fc45678, 0x7f800000]),
        _fromWords([0, 0x80000000, 0x7fc00001]),
      ];
      final frozen = [for (final point in sequence) _bits(point.storage)];
      for (final reuse in [false, true]) {
        final actualMatrix = _SequenceMatrix(sequence, reuseOutput: reuse);
        final beforeMatrix = _SequenceMatrix(sequence, reuseOutput: reuse);
        final box = vr.Aabb(
          min: vm.Vector3(-1, -2, -3),
          max: vm.Vector3(4, 5, 6),
        );
        final result = box.transformed(actualMatrix);
        final expected = _BeforeAabb(
          min: box.min,
          max: box.max,
        ).transformed(beforeMatrix);
        expect(actualMatrix.calls, 8);
        expect(actualMatrix.argumentBits, beforeMatrix.argumentBits);
        expect(
          _boundBits(result.min, result.max),
          _boundBits(expected.min, expected.max),
        );
        expect([for (final p in sequence) _bits(p.storage)], frozen);
        expect([for (final p in actualMatrix.values) _bits(p.storage)], frozen);
        for (final point in actualMatrix.outputs) {
          expect(identical(result.min, point), isFalse);
          expect(identical(result.max, point), isFalse);
        }
        final outputsBeforeMutation = [
          for (final p in actualMatrix.outputs) _bits(p.storage),
        ];
        result.min.setValues(9, 10, 11);
        result.max.setValues(12, 13, 14);
        expect([
          for (final p in actualMatrix.outputs) _bits(p.storage),
        ], outputsBeforeMutation);
      }
    },
  );

  test(
    'shared input vectors, overlapping storage and matrix aliases are not mutated',
    () {
      for (final aliasMatrix in [false, true]) {
        final words = Float32List(20);
        words.setAll(0, [1, 2, 3, 0, -4, 5, 6, 0, 0, 0, 1, 0, 3, 4, 5, 1]);
        final matrix = aliasMatrix
            ? vm.Matrix4.fromFloat32List(Float32List.view(words.buffer, 0, 16))
            : vm.Matrix4.identity();
        final low = vm.Vector3.fromFloat32List(
          Float32List.view(words.buffer, 0, 3),
        );
        final high = vm.Vector3.fromFloat32List(
          Float32List.view(words.buffer, 4, 3),
        );
        final originalWords = _bits(words), matrixBits = _bits(matrix.storage);
        final box = vr.Aabb(min: low, max: high);
        final expected = _BeforeAabb(
          min: _copyVector(low),
          max: _copyVector(high),
        ).transformed(vm.Matrix4.fromFloat32List(_copyStorage(matrix.storage)));
        final first = box.transformed(matrix), second = box.transformed(matrix);
        expect(
          _boundBits(first.min, first.max),
          _boundBits(expected.min, expected.max),
        );
        expect(_bits(words), originalWords);
        expect(_bits(matrix.storage), matrixBits);
        expect(identical(first.min, second.min), isFalse);
        expect(identical(first.max, second.max), isFalse);
        final secondBits = _boundBits(second.min, second.max);
        first.min.setValues(20, 21, 22);
        first.max.setValues(23, 24, 25);
        expect(_boundBits(second.min, second.max), secondBits);
        expect(_bits(words), originalWords);
        expect(_bits(matrix.storage), matrixBits);
      }
      final point = _fromWords([0x80000000, 0x3f800000, 0x7fc01234]);
      final pointBits = _bits(point.storage);
      final box = vr.Aabb(min: point, max: point);
      final result = box.transformed(vm.Matrix4.identity());
      final expected = _BeforeAabb(
        min: _copyVector(point),
        max: _copyVector(point),
      ).transformed(vm.Matrix4.identity());
      expect(
        _boundBits(result.min, result.max),
        _boundBits(expected.min, expected.max),
      );
      expect(_bits(point.storage), pointBits);
      expect(identical(result.min, point), isFalse);
      expect(identical(result.max, point), isFalse);
    },
  );

  test(
    'public expandToInclude still replaces vectors and preserves callers',
    () {
      final low = vm.Vector3(-1, -2, -3), high = vm.Vector3(4, 5, 6);
      final box = vr.Aabb(min: low, max: high);
      final before = _BeforeAabb(min: _copyVector(low), max: _copyVector(high));
      final lowBits = _bits(low.storage), highBits = _bits(high.storage);
      final point = vm.Vector3(0, 0, 0);
      box.expandToInclude(point);
      before.expandToInclude(point);
      expect(identical(box.min, low), isFalse);
      expect(identical(box.max, high), isFalse);
      expect(_bits(low.storage), lowBits);
      expect(_bits(high.storage), highBits);
      expect(_boundBits(box.min, box.max), _boundBits(before.min, before.max));
    },
  );

  test('1536 seeded finite affine and non-affine cases are bit equivalent', () {
    final random = math.Random(0xAABB054);
    double value() => (random.nextDouble() * 2 - 1) * 1000;
    for (var i = 0; i < 1536; i++) {
      final low = vm.Vector3(value(), value(), value());
      final high = vm.Vector3(value(), value(), value());
      final matrix = vm.Matrix4.fromList(
        List.generate(16, (_) => value() / 100),
      );
      if (i.isEven) {
        matrix.setEntry(3, 0, 0);
        matrix.setEntry(3, 1, 0);
        matrix.setEntry(3, 2, 0);
        matrix.setEntry(3, 3, 1);
      }
      _equivalent('seeded finite $i', low, high, matrix);
    }
  });

  test('512 seeded raw Float32 cases include NaN payloads and signed zero', () {
    final random = math.Random(0xF32054);
    int word() => random.nextInt(0x10000) | (random.nextInt(0x10000) << 16);
    const edges = [
      0,
      0x80000000,
      1,
      0x80000001,
      0x7f800000,
      0xff800000,
      0x7fc01234,
      0xffc05678,
      0x7f7fffff,
      0xff7fffff,
    ];
    int sample() =>
        random.nextInt(3) == 0 ? edges[random.nextInt(edges.length)] : word();
    for (var i = 0; i < 512; i++) {
      _equivalent(
        'seeded raw $i',
        _fromWords(List.generate(3, (_) => sample())),
        _fromWords(List.generate(3, (_) => sample())),
        _matrixFromWords(List.generate(16, (_) => sample())),
      );
    }
  });
}

// Literal relevant BEFORE implementation. Only class/type prefixes differ from
// the original file identified by _beforeSha256; all eight corners, virtual
// matrix calls and strict ternary/Vector3 reductions retain their old order.
class _BeforeAabb {
  vm.Vector3 min;
  vm.Vector3 max;

  _BeforeAabb({vm.Vector3? min, vm.Vector3? max})
    : min =
          min ?? vm.Vector3(double.infinity, double.infinity, double.infinity),
      max =
          max ??
          vm.Vector3(
            double.negativeInfinity,
            double.negativeInfinity,
            double.negativeInfinity,
          );

  void expandToInclude(vm.Vector3 point) {
    min = vm.Vector3(
      point.x < min.x ? point.x : min.x,
      point.y < min.y ? point.y : min.y,
      point.z < min.z ? point.z : min.z,
    );
    max = vm.Vector3(
      point.x > max.x ? point.x : max.x,
      point.y > max.y ? point.y : max.y,
      point.z > max.z ? point.z : max.z,
    );
  }

  _BeforeAabb transformed(vm.Matrix4 matrix) {
    final corners = [
      vm.Vector3(min.x, min.y, min.z),
      vm.Vector3(max.x, min.y, min.z),
      vm.Vector3(min.x, max.y, min.z),
      vm.Vector3(max.x, max.y, min.z),
      vm.Vector3(min.x, min.y, max.z),
      vm.Vector3(max.x, min.y, max.z),
      vm.Vector3(min.x, max.y, max.z),
      vm.Vector3(max.x, max.y, max.z),
    ];
    final result = _BeforeAabb();
    for (final corner in corners) {
      final transformed = matrix.transformed3(corner);
      result.expandToInclude(transformed);
    }
    return result;
  }
}
