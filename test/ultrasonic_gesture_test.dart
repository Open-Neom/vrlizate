import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('UltrasonicGestureChannel', () {
    const config = UltrasonicGestureConfig(
      sampleRate: 48000,
      carrierFrequency: 19000,
      fftSize: 1024,
      bandwidth: 1200,
      presenceThreshold: 1.8,
      dopplerThreshold: 120,
      gestureCooldown: Duration(milliseconds: 300),
    );

    /// Synthesizes microphone PCM: direct carrier leakage plus a Doppler
    /// shifted echo (as a hand moving at [dopplerHz] would reflect).
    List<double> synthEcho(int samples, double dopplerHz, double echoAmp) {
      final carrier = config.carrierFrequency;
      final sr = config.sampleRate.toDouble();
      return List<double>.generate(samples, (n) {
        final t = n / sr;
        final direct = 0.05 * math.sin(2 * math.pi * carrier * t);
        final echo =
            echoAmp * math.sin(2 * math.pi * (carrier + dopplerHz) * t);
        return direct + echo;
      });
    }

    test('tone generator produces the configured inaudible carrier', () {
      final channel = UltrasonicGestureChannel(config: config);
      final tone = channel.generateTone(4800);
      expect(tone.length, 4800);
      // A pure sine at amplitude 0.6 peaks near ±0.6.
      final peak = tone.map((v) => v.abs()).reduce(math.max);
      expect(peak, closeTo(0.6, 0.05));
    });

    test('silence keeps the hand absent and emits nothing', () {
      final channel = UltrasonicGestureChannel(config: config);
      final events = <UltrasonicGesture>[];
      channel.onGesture = (e) => events.add(e.gesture);

      channel.feedPcm(List<double>.filled(4096, 0.0001));
      expect(channel.handPresent, isFalse);
      expect(events, isEmpty);
    });

    test(
      'approaching hand (positive Doppler) triggers hoverEnter then push',
      () {
        final channel = UltrasonicGestureChannel(config: config);
        final events = <UltrasonicGesture>[];
        channel.onGesture = (e) => events.add(e.gesture);

        // Warm up the noise floor with near-silence.
        channel.feedPcm(List<double>.filled(2048, 0.0001));

        // Hand approaches: echo shifted +400 Hz above the carrier.
        channel.feedPcm(synthEcho(4096, 400, 0.5));

        expect(channel.handPresent, isTrue);
        expect(events, contains(UltrasonicGesture.hoverEnter));
        expect(events, contains(UltrasonicGesture.push));
        expect(events, isNot(contains(UltrasonicGesture.pull)));
      },
    );

    test('receding hand (negative Doppler) triggers pull', () {
      final channel = UltrasonicGestureChannel(config: config);
      final events = <UltrasonicGesture>[];
      channel.onGesture = (e) => events.add(e.gesture);

      channel.feedPcm(List<double>.filled(2048, 0.0001));
      channel.feedPcm(synthEcho(4096, -500, 0.5));

      expect(events, contains(UltrasonicGesture.pull));
      expect(events, isNot(contains(UltrasonicGesture.push)));
    });

    test('hand leaving the zone emits hoverExit', () {
      final channel = UltrasonicGestureChannel(config: config);
      final events = <UltrasonicGesture>[];
      channel.onGesture = (e) => events.add(e.gesture);

      channel.feedPcm(List<double>.filled(2048, 0.0001));
      channel.feedPcm(synthEcho(4096, 0, 0.5)); // Present, stationary.
      expect(channel.handPresent, isTrue);

      channel.feedPcm(List<double>.filled(4096, 0.0001)); // Hand leaves.
      expect(channel.handPresent, isFalse);
      expect(events, contains(UltrasonicGesture.hoverExit));
    });

    test('gesture cooldown suppresses rapid repeated pushes', () {
      final channel = UltrasonicGestureChannel(config: config);
      final events = <UltrasonicGesture>[];
      channel.onGesture = (e) => events.add(e.gesture);

      channel.feedPcm(List<double>.filled(2048, 0.0001));
      // Two pushes back-to-back: only one survives the cooldown because
      // feedPcm processes synchronously in wall-clock time.
      channel.feedPcm(synthEcho(4096, 400, 0.5));
      channel.feedPcm(synthEcho(4096, 400, 0.5));

      final pushes = events.where((e) => e == UltrasonicGesture.push).length;
      expect(pushes, 1);
    });
  });
}
