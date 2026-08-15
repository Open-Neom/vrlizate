import 'dart:async';

import 'package:vector_math/vector_math.dart';

import 'background_isolate.dart';

/// Represents a physical entity tracked in the room through WiFi CSI (Channel State Information).
class WifiTrackedSubject {
  final String id;
  Vector3 position;
  double
  respirationRate; // breaths per minute, a key SOTA feature of WiFi sensing!
  double movementIntensity;
  bool isMoving;

  WifiTrackedSubject({
    required this.id,
    required this.position,
    this.respirationRate = 16.0,
    this.movementIntensity = 0.0,
    this.isMoving = false,
  });
}

/// A simulated raw Channel State Information frame.
/// Represents OFDM subcarrier amplitudes affected by human movement.
class CsiFrame {
  final int timestamp;
  final List<double> amplitudes;

  CsiFrame({required this.timestamp, required this.amplitudes});
}

/// SOTA WiFi Sensing Engine that processes raw CSI frames in a background Isolate
/// to track movement, presence, and vitals (respiration) of human subjects.
class WifiSensingSystem {
  final List<WifiTrackedSubject> trackedSubjects = [];
  bool isActive = false;

  BackgroundIsolate? _processingIsolate;
  // The worker's SendPort (typed dynamically to stay WASM-compatible).
  dynamic _isolateSendPort;

  StreamController<List<WifiTrackedSubject>>? _streamController;
  Stream<List<WifiTrackedSubject>> get onSubjectsUpdated =>
      _streamController!.stream;

  WifiSensingSystem() {
    _streamController = StreamController<List<WifiTrackedSubject>>.broadcast();
  }

  /// Initializes the background processing Isolate for CSI data processing.
  Future<void> start() async {
    if (isActive) return;
    isActive = true;

    final isolate = BackgroundIsolate.create();
    _processingIsolate = isolate;

    // Listen for processed results from Isolate
    isolate.messages.listen((message) {
      if (message is Map<String, dynamic>) {
        _handleIsolateUpdate(message);
      } else {
        // First message: the worker's SendPort (two-way channel)
        _isolateSendPort = message;
      }
    });

    await isolate.start(wifiCsiProcessingEntry);
  }

  void _handleIsolateUpdate(Map<String, dynamic> data) {
    final id = data['id'] as String;
    final px = data['px'] as double;
    final py = data['py'] as double;
    final pz = data['pz'] as double;
    final resp = data['respiration'] as double;
    final intensity = data['intensity'] as double;
    final moving = data['isMoving'] as bool;

    // Update or add subject
    final idx = trackedSubjects.indexWhere((s) => s.id == id);
    if (idx != -1) {
      trackedSubjects[idx].position = Vector3(px, py, pz);
      trackedSubjects[idx].respirationRate = resp;
      trackedSubjects[idx].movementIntensity = intensity;
      trackedSubjects[idx].isMoving = moving;
    } else {
      trackedSubjects.add(
        WifiTrackedSubject(
          id: id,
          position: Vector3(px, py, pz),
          respirationRate: resp,
          movementIntensity: intensity,
          isMoving: moving,
        ),
      );
    }

    _streamController?.add(List.from(trackedSubjects));
  }

  /// Feeds simulated raw CSI frame into the background Isolate for processing
  void feedRawCsi(CsiFrame frame) {
    if (_isolateSendPort == null) return;
    _isolateSendPort!.send({
      'timestamp': frame.timestamp,
      'amplitudes': frame.amplitudes,
    });
  }

  void dispose() {
    isActive = false;
    _processingIsolate?.dispose();
    _processingIsolate = null;
    _isolateSendPort = null;
    _streamController?.close();
  }
}
