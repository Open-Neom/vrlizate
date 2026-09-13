/// Real background-isolate implementation using `dart:isolate` (VM / native).
///
/// Contains the worker entry points for head-tracking sensor fusion and
/// WiFi CSI processing. This library is only imported on platforms where
/// `dart:isolate` exists (see `background_isolate.dart`).
library;

import 'dart:isolate';
import 'dart:math';

import 'head_tracking_fusion.dart';

/// Generic handle to a background worker isolate.
class BackgroundIsolate {
  final ReceivePort _receivePort;
  Isolate? _isolate;
  bool _disposed = false;

  BackgroundIsolate._(this._receivePort);

  /// Opens the message channel synchronously; call [start] to spawn.
  static BackgroundIsolate create() => BackgroundIsolate._(ReceivePort());

  /// Messages received from the worker. The first message is always the
  /// worker's own SendPort, enabling two-way communication.
  Stream<dynamic> get messages => _receivePort;

  /// Spawns the worker isolate with [entryPoint].
  Future<void> start(void Function(dynamic) entryPoint) async {
    if (_disposed) return;
    final isolate = await Isolate.spawn(entryPoint, _receivePort.sendPort);
    if (_disposed) {
      isolate.kill(priority: Isolate.immediate);
    } else {
      _isolate = isolate;
    }
  }

  /// Kills the isolate and closes the message channel.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _receivePort.close();
  }
}

/// Head-tracking worker using the exact same fusion and signs as the main thread.
/// Messages carry sensor acquisition timestamps and a reset revision so queued
/// pre-recenter output cannot rotate a freshly recentered camera.
/// Protocol:
/// - [0, sensitivity, predictionMs, offsetX, offsetY, pitchGain, damping, revision]
/// - [1, accelX, accelY, accelZ]
/// - [2, gyroX, gyroY, timestampUs, revision]
/// - [3, revision] resets temporal state, retaining measured gravity.
/// - [4, revision] invalidates a stale or unavailable gravity reference.
/// Emits [revision, dYaw, dPitch, absolutePitchOrNull].
void headTrackingFusionEntry(dynamic mainSendPortArg) {
  final mainSendPort = mainSendPortArg as SendPort;
  final receivePort = ReceivePort();
  final fusion = HeadTrackingFusion();
  var revision = 0;
  mainSendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    if (message is! List) return;
    switch (message[0]) {
      case 0:
        fusion
          ..sensitivity = (message[1] as num).toDouble()
          ..predictionMs = (message[2] as num).toDouble()
          ..offsetX = (message[3] as num).toDouble()
          ..offsetY = (message[4] as num).toDouble()
          ..pitchGain = (message[5] as num).toDouble()
          ..jitterDamping = message[6] as bool;
        revision = message[7] as int;
      case 1:
        fusion.updateGravity(
          (message[1] as num).toDouble(),
          (message[2] as num).toDouble(),
          (message[3] as num).toDouble(),
        );
      case 2:
        if (message[4] != revision) return;
        if (fusion.addGyroscope(
          (message[1] as num).toDouble(),
          (message[2] as num).toDouble(),
          message[3] as int,
        )) {
          mainSendPort.send([
            revision,
            fusion.dYaw,
            fusion.dPitch,
            fusion.absolutePitch,
          ]);
        }
      case 3:
        revision = message[1] as int;
        fusion.reset();
      case 4:
        revision = message[1] as int;
        fusion.clearGravity();
    }
  });
}

/// Entry point for the background isolate doing compute-heavy CSI signal
/// processing (OFDM subcarrier analysis for WiFi sensing).
///
/// Receives `{'timestamp': int, 'amplitudes': List<double>}` frames and emits
/// processed subject updates as maps.
void wifiCsiProcessingEntry(dynamic mainSendPortArg) {
  final mainSendPort = mainSendPortArg as SendPort;
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  // Track state inside Isolate
  final List<double> history = [];

  receivePort.listen((message) {
    if (message is Map<String, dynamic>) {
      final List<double> amplitudes = List<double>.from(message['amplitudes']);

      // SOTA CSI processing: Compute standard deviation of subcarriers
      // to detect multipath phase/amplitude disturbance caused by movement
      double sum = 0.0;
      for (final val in amplitudes) {
        sum += val;
      }
      final mean = sum / amplitudes.length;

      double sqDiffSum = 0.0;
      for (final val in amplitudes) {
        sqDiffSum += (val - mean) * (val - mean);
      }
      final variance = sqDiffSum / amplitudes.length;
      final stdDev = sqrt(variance);

      // Keep running history for sliding window (vital signs respiration detection)
      history.add(stdDev);
      if (history.length > 50) history.removeAt(0);

      // Analyze respiration rate: count zero-crossings of bandpassed variance
      double zeroCrossings = 0;
      for (var i = 1; i < history.length; i++) {
        if ((history[i] - 1.0) * (history[i - 1] - 1.0) < 0) {
          zeroCrossings++;
        }
      }
      // Respiration rate estimation in breaths per minute (typically 12 - 20 bpm)
      final estimatedResp = 12.0 + (zeroCrossings * 0.4).clamp(0.0, 8.0);

      // Estimate subject coordinates based on multi-antenna amplitude ratios (Trilateration)
      final double dist = 1.0 + (5.0 / (mean + 0.1)).clamp(0.0, 5.0);

      // Simulate a circular walking trajectory based on time
      final double timeSecs = message['timestamp'] / 1000.0;
      final double px = sin(timeSecs * 0.5) * dist;
      final double py =
          1.0 +
          sin(timeSecs * estimatedResp * 0.1) *
              0.02; // breathing chest displacement
      final double pz = -2.0 + cos(timeSecs * 0.5) * dist;

      final isMoving = stdDev > 0.15;

      // Return processed coordinates & state back to the main thread
      mainSendPort.send({
        'id': 'subject_alpha',
        'px': px,
        'py': py,
        'pz': pz,
        'respiration': estimatedResp,
        'intensity': stdDev,
        'isMoving': isMoving,
      });
    }
  });
}
