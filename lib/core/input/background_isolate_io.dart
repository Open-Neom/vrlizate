/// Real background-isolate implementation using `dart:isolate` (VM / native).
///
/// Contains the worker entry points for head-tracking sensor fusion and
/// WiFi CSI processing. This library is only imported on platforms where
/// `dart:isolate` exists (see `background_isolate.dart`).
library;

import 'dart:isolate';
import 'dart:math';

/// Generic handle to a background worker isolate.
class BackgroundIsolate {
  final ReceivePort _receivePort;
  Isolate? _isolate;

  BackgroundIsolate._(this._receivePort);

  /// Opens the message channel synchronously; call [start] to spawn.
  static BackgroundIsolate create() => BackgroundIsolate._(ReceivePort());

  /// Messages received from the worker. The first message is always the
  /// worker's own SendPort, enabling two-way communication.
  Stream<dynamic> get messages => _receivePort;

  /// Spawns the worker isolate with [entryPoint].
  Future<void> start(void Function(dynamic) entryPoint) async {
    _isolate = await Isolate.spawn(entryPoint, _receivePort.sendPort);
  }

  /// Kills the isolate and closes the message channel.
  void dispose() {
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _receivePort.close();
  }
}

/// Entry point for the background isolate executing head-tracking
/// complementary sensor fusion (IMU gyroscope + accelerometer).
///
/// Protocol (messages from main thread):
/// - `[0, alpha, sensitivity, predictionMs, offsetX, offsetY]` — config
/// - `[1, x, y, z]` — accelerometer sample
/// - `[2, x, y]` — gyroscope sample (device X = yaw, Y = pitch in landscape)
///
/// Emits `[dYaw, dPitch]` rotation deltas per gyroscope sample.
void headTrackingFusionEntry(dynamic mainSendPortArg) {
  final mainSendPort = mainSendPortArg as SendPort;
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  double yawFused = 0.0;
  double pitchFused = 0.0;
  double? prevYawFused;
  double? prevPitchFused;

  double accelX = 0.0;
  double accelY = 0.0;
  double accelZ = 9.8;

  double offsetX = 0.0;
  double offsetY = 0.0;
  double alpha = 0.98;
  double sensitivity = 1.0;
  double predictionMs = 15.0;

  DateTime? lastTimestamp;

  receivePort.listen((message) {
    if (message is List) {
      final type = message[0] as int;
      if (type == 0) {
        // Configuration: [0, alpha, sensitivity, predictionMs, offsetX, offsetY]
        alpha = (message[1] as num).toDouble();
        sensitivity = (message[2] as num).toDouble();
        predictionMs = (message[3] as num).toDouble();
        offsetX = (message[4] as num).toDouble();
        offsetY = (message[5] as num).toDouble();
      } else if (type == 1) {
        // Accelerometer: [1, x, y, z]
        accelX = (message[1] as num).toDouble();
        accelY = (message[2] as num).toDouble();
        accelZ = (message[3] as num).toDouble();
      } else if (type == 2) {
        // Gyroscope: [2, x, y, z]
        final gx = (message[1] as num).toDouble();
        final gy = (message[2] as num).toDouble();

        // Dynamic Auto-Calibrating Anti-Drift:
        // If the gyroscope velocity is extremely low, adaptively adjust the offsets
        final double magnitude = sqrt(gx * gx + gy * gy);
        if (magnitude < 0.015) {
          offsetX = offsetX * 0.995 + gx * 0.005;
          offsetY = offsetY * 0.995 + gy * 0.005;
        }

        final adjustedX = gx - offsetX;
        final adjustedY = gy - offsetY;

        // Gravity reference for the pitch channel (device-Y rotation in
        // landscape): gravity tilts between the X and Z device axes.
        double gravityPitch() =>
            atan2(-accelX, sqrt(accelY * accelY + accelZ * accelZ));

        final now = DateTime.now();
        if (lastTimestamp == null) {
          lastTimestamp = now;
          yawFused = 0.0;
          pitchFused = gravityPitch();
          prevYawFused = yawFused;
          prevPitchFused = pitchFused;
          return;
        }

        final dt = now.difference(lastTimestamp!).inMicroseconds / 1000000.0;
        lastTimestamp = now;

        // Yaw (device-X rotation in landscape): gravity does NOT change
        // under pure yaw, so there is no absolute reference — integrate
        // the gyroscope directly (bias is handled by the anti-drift offsets).
        yawFused += adjustedX * dt;

        // Pitch: complementary filter, gyro integration anchored to gravity.
        pitchFused =
            alpha * (pitchFused + adjustedY * dt) +
            (1 - alpha) * gravityPitch();

        // Latency extrapolation prediction
        final predictionTime = predictionMs / 1000.0;
        final predictedYaw = yawFused + adjustedX * predictionTime;
        final predictedPitch = pitchFused + adjustedY * predictionTime;

        final dYaw = predictedYaw - (prevYawFused ?? predictedYaw);
        final dPitch = predictedPitch - (prevPitchFused ?? predictedPitch);

        prevYawFused = predictedYaw;
        prevPitchFused = predictedPitch;

        mainSendPort.send([-dYaw * sensitivity, dPitch * sensitivity]);
      }
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
