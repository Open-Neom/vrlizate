import 'dart:async';
import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// A Wi-Fi RTT (IEEE 802.11mc) anchor: an access point or RTT-capable device
/// with a known physical position in the room.
class WifiRttAnchor {
  /// Identifier (typically the AP BSSID).
  final String id;

  /// Anchor position in meters, in a room-local coordinate frame.
  final Vector3 position;

  const WifiRttAnchor({required this.id, required this.position});
}

/// A single round-trip-time distance measurement to an anchor.
class RttMeasurement {
  final String anchorId;

  /// Measured distance to the anchor in meters.
  final double distanceMeters;

  /// Standard deviation of the measurement, if reported by the radio.
  final double? stdDevMeters;

  final DateTime timestamp;

  RttMeasurement({
    required this.anchorId,
    required this.distanceMeters,
    this.stdDevMeters,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Room-scale position estimate produced by [WifiRttPositioning].
class RttPosition {
  final Vector3 position;

  /// Root-mean-square residual of the trilateration (meters). Lower is
  /// better; values above ~1.5 m indicate inconsistent measurements.
  final double residualRms;

  /// Number of anchors used in the fix.
  final int anchorsUsed;

  final DateTime timestamp;

  RttPosition({
    required this.position,
    required this.residualRms,
    required this.anchorsUsed,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Whether the device reports Wi-Fi RTT support. Resolved natively by the
/// host app (`WifiRttManager.isAvailable` on Android 9+) and passed to
/// [WifiRttPositioning.capability].
enum WifiRttCapability { unknown, supported, unsupported }

/// Room-scale positioning via Wi-Fi RTT (IEEE 802.11mc / FTM).
///
/// Unlike CSI-based Wi-Fi sensing (which requires rooted firmware such as
/// Nexmon and is not accessible on stock Android), RTT ranging is available
/// through the public Android API on Android 9+ with 1–2 m accuracy.
///
/// The engine is transport-agnostic: the host app performs the native RTT
/// scans and feeds [RttMeasurement]s here; this class solves the
/// trilateration with weighted Gauss-Newton least squares and publishes a
/// smoothed room-local position.
class WifiRttPositioning {
  /// Registered anchors with known room-local positions.
  final Map<String, WifiRttAnchor> anchors = {};

  /// Maximum age of a measurement to be used in a fix.
  Duration measurementWindow;

  /// Residual (meters) above which a measurement is rejected as an outlier
  /// and the fix is recomputed without it.
  double outlierThreshold;

  /// Smoothing factor for the published position (0 = frozen, 1 = raw).
  double smoothing;

  /// Device capability as reported by the host app.
  WifiRttCapability capability = WifiRttCapability.unknown;

  final List<RttMeasurement> _recent = [];

  final StreamController<RttPosition> _positionController =
      StreamController<RttPosition>.broadcast();

  /// Stream of room-local position fixes.
  Stream<RttPosition> get onPosition => _positionController.stream;

  /// Latest position fix, if any.
  RttPosition? get lastPosition => _lastPosition;
  RttPosition? _lastPosition;

  WifiRttPositioning({
    this.measurementWindow = const Duration(seconds: 2),
    this.outlierThreshold = 2.0,
    this.smoothing = 0.4,
  });

  /// Registers or updates an anchor position.
  void addAnchor(WifiRttAnchor anchor) => anchors[anchor.id] = anchor;

  /// Removes an anchor by id.
  void removeAnchor(String id) => anchors.remove(id);

  /// Feeds one RTT measurement; recomputes the position fix when enough
  /// fresh measurements are available.
  void feedMeasurement(RttMeasurement m) {
    if (!anchors.containsKey(m.anchorId)) return;
    _recent.add(m);
    _prune(m.timestamp);
    _solve(m.timestamp);
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(measurementWindow);
    _recent.removeWhere((m) => m.timestamp.isBefore(cutoff));
  }

  void _solve(DateTime now) {
    // Use the freshest measurement per anchor.
    final freshest = <String, RttMeasurement>{};
    for (final m in _recent) {
      final prev = freshest[m.anchorId];
      if (prev == null || m.timestamp.isAfter(prev.timestamp)) {
        freshest[m.anchorId] = m;
      }
    }
    if (freshest.length < 3) return; // Need >= 3 anchors for a 2D/3D fix.

    var used = freshest.values.toList();
    var result = _leastSquares(used);

    // Outlier rejection: drop the worst measurement and re-solve once.
    if (result != null &&
        result.residualRms > outlierThreshold &&
        used.length > 3) {
      var worstIdx = 0;
      var worstResidual = 0.0;
      for (var i = 0; i < used.length; i++) {
        final anchor = anchors[used[i].anchorId]!;
        final r =
            ((result.position - anchor.position).length -
                    used[i].distanceMeters)
                .abs();
        if (r > worstResidual) {
          worstResidual = r;
          worstIdx = i;
        }
      }
      used = List.of(used)..removeAt(worstIdx);
      result = _leastSquares(used) ?? result;
    }

    if (result == null) return;

    // Smooth against the previous fix to avoid jumps.
    final prev = _lastPosition;
    final smoothed = prev == null
        ? result.position
        : prev.position + (result.position - prev.position) * smoothing;

    _lastPosition = RttPosition(
      position: smoothed,
      residualRms: result.residualRms,
      anchorsUsed: result.anchorsUsed,
      timestamp: now,
    );
    _positionController.add(_lastPosition!);
  }

  /// Weighted Gauss-Newton trilateration. Weights favor measurements with
  /// low reported standard deviation.
  RttPosition? _leastSquares(List<RttMeasurement> measurements) {
    // Initial guess: weighted centroid of anchor positions.
    var estimate = Vector3.zero();
    var wSum = 0.0;
    final weights = <double>[];
    for (final m in measurements) {
      final w = 1.0 / math.pow(m.stdDevMeters ?? 1.0, 2);
      weights.add(w.toDouble());
      estimate += anchors[m.anchorId]!.position * w;
      wSum += w;
    }
    if (wSum <= 0) return null;
    estimate /= wSum;

    for (var iter = 0; iter < 12; iter++) {
      final n = measurements.length;
      // Normal equations JᵀWJ Δ = JᵀWr for a 3-DOF position.
      final a = List<double>.filled(9, 0); // 3x3 symmetric
      final b = List<double>.filled(3, 0);

      for (var i = 0; i < n; i++) {
        final anchor = anchors[measurements[i].anchorId]!.position;
        final diff = estimate - anchor;
        final dist = diff.length;
        if (dist < 1e-6) continue;
        final residual = dist - measurements[i].distanceMeters;
        final w = weights[i];
        final j = [diff.x / dist, diff.y / dist, diff.z / dist];

        for (var r = 0; r < 3; r++) {
          b[r] += w * j[r] * residual;
          for (var c = 0; c <= r; c++) {
            a[r * 3 + c] += w * j[r] * j[c];
          }
        }
      }
      // Mirror symmetric entries.
      a[1 * 3 + 2] = a[2 * 3 + 1];
      a[0 * 3 + 2] = a[2 * 3 + 0];
      a[0 * 3 + 1] = a[1 * 3 + 0];

      // Levenberg damping: keeps the system solvable when anchors are
      // (near-)coplanar with the estimate, e.g. all APs on the ceiling.
      final trace = (a[0] + a[4] + a[8]).abs();
      final lambda = 1e-9 * (trace > 1 ? trace : 1.0);
      a[0] += lambda;
      a[4] += lambda;
      a[8] += lambda;

      final delta = _solve3x3(a, b);
      if (delta == null) return null;
      estimate -= delta;
      if (delta.length < 1e-4) break;
    }

    // Final RMS residual.
    var sumSq = 0.0;
    for (final m in measurements) {
      final r =
          (estimate - anchors[m.anchorId]!.position).length - m.distanceMeters;
      sumSq += r * r;
    }

    return RttPosition(
      position: estimate,
      residualRms: math.sqrt(sumSq / measurements.length),
      anchorsUsed: measurements.length,
    );
  }

  /// Solves a symmetric 3x3 system via Gaussian elimination with pivoting.
  static Vector3? _solve3x3(List<double> a, List<double> b) {
    final m = [
      [a[0], a[1], a[2], b[0]],
      [a[3], a[4], a[5], b[1]],
      [a[6], a[7], a[8], b[2]],
    ];
    for (var col = 0; col < 3; col++) {
      var pivot = col;
      for (var row = col + 1; row < 3; row++) {
        if (m[row][col].abs() > m[pivot][col].abs()) pivot = row;
      }
      if (m[pivot][col].abs() < 1e-12) return null;
      final tmp = m[col];
      m[col] = m[pivot];
      m[pivot] = tmp;
      for (var row = 0; row < 3; row++) {
        if (row == col) continue;
        final f = m[row][col] / m[col][col];
        for (var k = col; k < 4; k++) {
          m[row][k] -= f * m[col][k];
        }
      }
    }
    return Vector3(m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2]);
  }

  void dispose() {
    _recent.clear();
    _positionController.close();
  }
}
