import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VrDirectDeviceBridge & VrDirectCoreMotion (Flutter 3.50+ FFIgen)', () {
    test('reads live native OS thermal status and capabilities on macOS/iOS', () {
      final bridge = VrDirectDeviceBridge.instance;
      if (Platform.isMacOS || Platform.isIOS) {
        expect(bridge.isAvailable, isTrue);

        final thermal = bridge.readThermalStatusSync();
        expect(thermal, isNotNull);
        expect(thermal, inInclusiveRange(0, 4));

        final caps = bridge.readDeviceCapabilitiesSync();
        expect(caps, isNotNull);
        expect(caps!['manufacturer'], equals('Apple'));
        expect(caps['totalRamMb'] as int, greaterThanOrEqualTo(1024));
        expect(caps['cpuCores'] as int, greaterThanOrEqualTo(1));
        expect(caps['supportedModes'], isA<List<Object?>>());
        expect((caps['supportedModes'] as List<Object?>), isNotEmpty);

        // Non-Android host safely returns null for Android-only JNI handles/SAF.
        expect(bridge.detachAndroidSafReadOnlyFdSync('content://test/world'), isNull);
        expect(bridge.androidOpenXrHandlesSync(), isNull);
      }
    });

    test('probes Apple CoreMotion framework safely without crashing without IMU', () {
      final cm = VrDirectCoreMotion.shared;
      if (Platform.isMacOS || Platform.isIOS) {
        expect(cm.isSupported, isTrue);
        if (!cm.isDeviceMotionAvailable) {
          expect(cm.startUpdates(), isFalse);
          expect(cm.readSampleSync(), isNull);
        }
      }
      expect(VrCoreMotionGyroscope.shared.readDirectSampleSync(), anyOf(isNull, isA<VrDirectMotionSample>()));
    });

    test('empirical micro-benchmark: Direct Native FFI vs MethodChannel round-trip', () async {
      final bridge = VrDirectDeviceBridge.instance;
      if (!bridge.isAvailable) return;

      const benchChannel = MethodChannel('vrlizate/bench_interop');
      const simulatedThermalReply = <String, Object?>{'thermalStatus': 0};
      const simulatedGyroFrame = <double>[0.014, -0.021, 0.003, 1794851238131000.0];
      final simulatedCapsReply = bridge.readDeviceCapabilitiesSync()!;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(benchChannel, (call) async {
            return switch (call.method) {
              'thermal' => simulatedThermalReply,
              'gyro' => simulatedGyroFrame,
              'caps' => simulatedCapsReply,
              _ => null,
            };
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(benchChannel, null);
      });

      // Warmup JIT across both code paths.
      for (var i = 0; i < 500; i++) {
        bridge.readThermalStatusSync();
        bridge.readDeviceCapabilitiesSync();
        VrDirectCoreMotion.shared.readSampleSync();
        await benchChannel.invokeMethod<Object?>('thermal');
        await benchChannel.invokeMethod<Object?>('gyro');
        await benchChannel.invokeMethod<Object?>('caps');
      }

      const iterations = 10000;

      // 1. Direct FFI/ObjC Thermal Read
      final swDirectThermal = Stopwatch()..start();
      var thermalAcc = 0;
      for (var i = 0; i < iterations; i++) {
        thermalAcc += bridge.readThermalStatusSync() ?? 0;
      }
      swDirectThermal.stop();

      // 2. Legacy MethodChannel Thermal Read
      final swChannelThermal = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        final res = await benchChannel.invokeMethod<Map<Object?, Object?>>('thermal');
        thermalAcc += (res?['thermalStatus'] as int?) ?? 0;
      }
      swChannelThermal.stop();

      // 3. Direct FFI/ObjC CoreMotion Sensor Poll
      final swDirectMotion = Stopwatch()..start();
      var motionHits = 0;
      for (var i = 0; i < iterations; i++) {
        if (VrDirectCoreMotion.shared.readSampleSync() != null) motionHits++;
      }
      swDirectMotion.stop();

      // 4. Legacy MethodChannel/StandardMessageCodec Sensor Frame
      final swChannelMotion = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        final res = await benchChannel.invokeMethod<List<Object?>>('gyro');
        if (res != null && res.length == 4) motionHits++;
      }
      swChannelMotion.stop();

      // 5. Direct FFI/ObjC Full Capabilities Snapshot vs MethodChannel
      const capIterations = 2000;
      final swDirectCaps = Stopwatch()..start();
      var ramSum = 0;
      for (var i = 0; i < capIterations; i++) {
        final c = bridge.readDeviceCapabilitiesSync();
        ramSum += (c?['totalRamMb'] as int?) ?? 0;
      }
      swDirectCaps.stop();

      final swChannelCaps = Stopwatch()..start();
      for (var i = 0; i < capIterations; i++) {
        final c = await benchChannel.invokeMethod<Map<Object?, Object?>>('caps');
        ramSum += (c?['totalRamMb'] as int?) ?? 0;
      }
      swChannelCaps.stop();

      final directThermalNs = (swDirectThermal.elapsedMicroseconds * 1000.0) / iterations;
      final channelThermalNs = (swChannelThermal.elapsedMicroseconds * 1000.0) / iterations;
      final directMotionNs = (swDirectMotion.elapsedMicroseconds * 1000.0) / iterations;
      final channelMotionNs = (swChannelMotion.elapsedMicroseconds * 1000.0) / iterations;
      final directCapsNs = (swDirectCaps.elapsedMicroseconds * 1000.0) / capIterations;
      final channelCapsNs = (swChannelCaps.elapsedMicroseconds * 1000.0) / capIterations;

      debugPrint(
        '[BENCHMARK_DIRECT_INTEROP] '
        'thermal_direct_ns=${directThermalNs.toStringAsFixed(1)} '
        'thermal_channel_ns=${channelThermalNs.toStringAsFixed(1)} '
        'thermal_speedup=${(channelThermalNs / directThermalNs).toStringAsFixed(1)}x | '
        'motion_direct_ns=${directMotionNs.toStringAsFixed(1)} '
        'motion_channel_ns=${channelMotionNs.toStringAsFixed(1)} '
        'motion_speedup=${(channelMotionNs / directMotionNs).toStringAsFixed(1)}x | '
        'caps_direct_ns=${directCapsNs.toStringAsFixed(1)} '
        'caps_channel_ns=${channelCapsNs.toStringAsFixed(1)} '
        'caps_speedup=${(channelCapsNs / directCapsNs).toStringAsFixed(1)}x '
        '(guard=${thermalAcc ^ motionHits ^ ramSum})',
      );

      expect(directThermalNs, lessThan(channelThermalNs));
      expect(directMotionNs, lessThan(channelMotionNs));
    });
  });
}
