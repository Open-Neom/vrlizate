import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Rigid Euclidean transform (`p_target = rotation * p_source + translation`,
/// `det(rotation) == +1`) computed by [KabschHorizonAligner].
class RigidTransform3D {
  RigidTransform3D({
    required Matrix3 rotation,
    required Vector3 translation,
    required this.rmsErrorMeters,
  }) : rotation = rotation.clone(),
       translation = translation.clone();

  final Matrix3 rotation;
  final Vector3 translation;
  final double rmsErrorMeters;

  Vector3 transform(Vector3 point) =>
      rotation.transformed(point) + translation;
}

/// Pure-Dart 3D Kabsch / orthogonal Procrustes rigid aligner (Kabsch 1976)
/// and camera horizon (`pitch` / `roll`) leveling utilities.
///
/// Handles both 3D point clouds and flat 2D calibration boards (`z = 0`)
/// without singularity while guaranteeing a proper right-handed rotation
/// (`det(R) == +1`).
abstract final class KabschHorizonAligner {
  /// Solves the optimal rigid transform mapping [sourcePoints] onto
  /// [targetPoints] (`target_i ≈ R * source_i + t`).
  ///
  /// Returns `null` if fewer than 3 finite, non-collinear correspondences exist.
  static RigidTransform3D? alignCorrespondingPoints({
    required List<Vector3> sourcePoints,
    required List<Vector3> targetPoints,
    double collinearityFloor = 1e-7,
  }) {
    if (sourcePoints.length != targetPoints.length || sourcePoints.length < 3) {
      return null;
    }

    final src = <Vector3>[];
    final dst = <Vector3>[];
    for (var i = 0; i < sourcePoints.length; i++) {
      final p = sourcePoints[i];
      final q = targetPoints[i];
      if (p.x.isFinite &&
          p.y.isFinite &&
          p.z.isFinite &&
          q.x.isFinite &&
          q.y.isFinite &&
          q.z.isFinite) {
        src.add(p);
        dst.add(q);
      }
    }
    final n = src.length;
    if (n < 3) return null;

    final srcCentroid = Vector3.zero();
    final dstCentroid = Vector3.zero();
    for (var i = 0; i < n; i++) {
      srcCentroid.add(src[i]);
      dstCentroid.add(dst[i]);
    }
    srcCentroid.scale(1.0 / n);
    dstCentroid.scale(1.0 / n);

    // Cross-covariance H = sum_i (p_i - p_bar) * (q_i - q_bar)^T
    // Wait: maximizing tr(R * H) gives R = V * U^T when H = U * Sigma * V^T,
    // which implies H^T * H = V * Sigma^2 * V^T! Wait: let's verify:
    // If q = R0 * p, then H = sum p * p^T * R0^T = C_p * R0^T.
    // Then H * H^T = C_p^2 -> eigenvectors of H * H^T are U (source axes),
    // and H^T * u_k = R0 * C_p * u_k = sigma_k * R0 * u_k -> v_k = R0 * u_k!
    // Look how clean THAT direction is:
    // Diagonalize S_src = sum_i p_tilde * p_tilde^T? No, diagonalize G = H * H^T!
    // Wait: let's check G = H * H^T when q = R0 * p + noise:
    // H = U * Sigma * V^T => G = H * H^T = U * Sigma^2 * U^T, and
    // H^T * u_k = V * Sigma * U^T * u_k = sigma_k * v_k!
    // That works identically and directly aligns u_0, u_1 with the two principal
    // axes of a planar board in source coordinates!
    final h = List<List<double>>.generate(
      3,
      (_) => List<double>.filled(3, 0.0),
    );
    for (var i = 0; i < n; i++) {
      final px = src[i].x - srcCentroid.x;
      final py = src[i].y - srcCentroid.y;
      final pz = src[i].z - srcCentroid.z;
      final qx = dst[i].x - dstCentroid.x;
      final qy = dst[i].y - dstCentroid.y;
      final qz = dst[i].z - dstCentroid.z;
      final pArr = <double>[px, py, pz];
      final qArr = <double>[qx, qy, qz];
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 3; c++) {
          h[r][c] += pArr[r] * qArr[c];
        }
      }
    }

    // Symmetric 3x3 matrix G = H * H^T = U * Sigma^2 * U^T
    final g = List<List<double>>.generate(
      3,
      (_) => List<double>.filled(3, 0.0),
    );
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        g[r][c] = h[r][0] * h[c][0] + h[r][1] * h[c][1] + h[r][2] * h[c][2];
      }
    }

    final eig = _jacobiSymmetric3x3(g);
    final order = <int>[0, 1, 2]
      ..sort((a, b) => eig.values[b].compareTo(eig.values[a]));

    final l0 = math.max(0.0, eig.values[order[0]]);
    final l1 = math.max(0.0, eig.values[order[1]]);
    if (l0 <= 1e-18 || l1 / l0 < collinearityFloor * collinearityFloor) {
      return null;
    }

    Vector3 colVec(List<List<double>> mat, int col) =>
        Vector3(mat[0][col], mat[1][col], mat[2][col]);

    final u0 = colVec(eig.vectors, order[0])..normalize();
    var u1 = colVec(eig.vectors, order[1]);
    u1 -= u0 * u0.dot(u1);
    if (u1.length2 < 1e-16) return null;
    u1.normalize();
    final u2 = u0.cross(u1)..normalize(); // Ensures det(U) == +1

    Vector3 hTransposeTimes(Vector3 u) => Vector3(
      h[0][0] * u.x + h[1][0] * u.y + h[2][0] * u.z,
      h[0][1] * u.x + h[1][1] * u.y + h[2][1] * u.z,
      h[0][2] * u.x + h[1][2] * u.y + h[2][2] * u.z,
    );

    final v0Raw = hTransposeTimes(u0);
    if (v0Raw.length2 < 1e-18) return null;
    final v0 = v0Raw.normalized();

    var v1 = hTransposeTimes(u1);
    v1 -= v0 * v0.dot(v1);
    if (v1.length2 < 1e-18) return null;
    v1.normalize();
    // Enforcing v2 = v0 x v1 guarantees det(V) == +1 -> det(R = V * U^T) == +1,
    // automatically handling both planar (sigma_2 == 0) and 3D reflection cases!
    final v2 = v0.cross(v1)..normalize();

    // R = v0 * u0^T + v1 * u1^T + v2 * u2^T
    final rot = Matrix3.zero();
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        final val =
            v0.storage[r] * u0.storage[c] +
            v1.storage[r] * u1.storage[c] +
            v2.storage[r] * u2.storage[c];
        rot.setEntry(r, c, val);
      }
    }

    final trans = dstCentroid - rot.transformed(srcCentroid);

    var sqErr = 0.0;
    for (var i = 0; i < n; i++) {
      final pred = rot.transformed(src[i]) + trans;
      sqErr += pred.distanceToSquared(dst[i]);
    }

    return RigidTransform3D(
      rotation: rot,
      translation: trans,
      rmsErrorMeters: math.sqrt(sqErr / n),
    );
  }

  /// Finds the longest contiguous frame interval `[start, endExclusive)` across
  /// `frames` (`frames[t][cornerIdx]`, `null` when unseen) where the median
  /// per-point frame-to-frame motion stays below [maxMotionPerFrameMeters].
  static (int start, int endExclusive)? findQuietFrameWindow(
    List<List<Vector3?>> frames, {
    double maxMotionPerFrameMeters = 0.0025,
    int minCommonCorners = 3,
    int minWindowFrames = 8,
  }) {
    final nFrames = frames.length;
    if (nFrames < minWindowFrames || nFrames < 2) return null;

    final stepMotion = List<double>.filled(nFrames - 1, double.infinity);
    for (var t = 0; t < nFrames - 1; t++) {
      final a = frames[t];
      final b = frames[t + 1];
      final count = math.min(a.length, b.length);
      final deltas = <double>[];
      for (var k = 0; k < count; k++) {
        final pa = a[k];
        final pb = b[k];
        if (pa != null && pb != null) {
          deltas.add(pa.distanceTo(pb));
        }
      }
      if (deltas.length >= minCommonCorners) {
        deltas.sort();
        stepMotion[t] = _medianSorted(deltas);
      }
    }

    int? bestStart;
    int? bestEnd;
    var bestMeanMotion = double.infinity;

    var t = 0;
    while (t < stepMotion.length) {
      if (stepMotion[t] >= maxMotionPerFrameMeters) {
        t++;
        continue;
      }
      final runStart = t;
      var sumMotion = 0.0;
      while (t < stepMotion.length && stepMotion[t] < maxMotionPerFrameMeters) {
        sumMotion += stepMotion[t];
        t++;
      }
      final runEnd = t + 1;
      final runLen = runEnd - runStart;
      if (runLen >= minWindowFrames) {
        final meanMotion = sumMotion / (t - runStart);
        final prevLen = bestStart == null ? 0 : (bestEnd! - bestStart);
        if (runLen > prevLen ||
            (runLen == prevLen && meanMotion < bestMeanMotion)) {
          bestStart = runStart;
          bestEnd = runEnd;
          bestMeanMotion = meanMotion;
        }
      }
    }

    return bestStart == null ? null : (bestStart, bestEnd!);
  }

  /// Computes per-index coordinate-wise median 3D positions across `[start, endExclusive)`,
  /// discarding indices seen fewer than [minObservations] times.
  static Map<int, Vector3> medianPointsInWindow(
    List<List<Vector3?>> frames,
    int start,
    int endExclusive, {
    int minObservations = 3,
  }) {
    if (frames.isEmpty || start >= endExclusive) return const <int, Vector3>{};
    final nPoints = frames[start].length;
    final out = <int, Vector3>{};

    for (var k = 0; k < nPoints; k++) {
      final xs = <double>[];
      final ys = <double>[];
      final zs = <double>[];
      for (var t = start; t < endExclusive; t++) {
        if (k >= frames[t].length) continue;
        final p = frames[t][k];
        if (p != null && p.x.isFinite && p.y.isFinite && p.z.isFinite) {
          xs.add(p.x);
          ys.add(p.y);
          zs.add(p.z);
        }
      }
      if (xs.length >= minObservations) {
        xs.sort();
        ys.sort();
        zs.sort();
        out[k] = Vector3(
          _medianSorted(xs),
          _medianSorted(ys),
          _medianSorted(zs),
        );
      }
    }
    return out;
  }

  /// Rotates a CV camera translation vector (`+X` camera-right, `+Y` camera-down,
  /// `+Z` optical axis forward) into a gravity-leveled room frame (`+X` user-right,
  /// `+Y` world-up, `+Z` horizontal depth from camera) given the camera's physical
  /// [pitchRadians] (`> 0` tilted upward toward ceiling, `< 0` tilted downward
  /// toward floor) and [rollRadians].
  static Vector3 levelCameraPointToHorizon(
    Vector3 pointCameraCv, {
    required double pitchRadians,
    double rollRadians = 0.0,
  }) {
    // Convert CV camera axes (+X cam-right = -user-right, +Y cam-down = -up, +Z depth)
    // into camera-aligned right-handed room axes: x = -X_cv, y = -Y_cv, z = +Z_cv.
    var x = -pointCameraCv.x;
    var y = -pointCameraCv.y;
    var z = pointCameraCv.z;

    if (rollRadians != 0.0) {
      final cr = math.cos(rollRadians);
      final sr = math.sin(rollRadians);
      final xr = cr * x - sr * y;
      final yr = sr * x + cr * y;
      x = xr;
      y = yr;
    }

    if (pitchRadians != 0.0) {
      // If camera is pitched UP by +pitchRadians, a point straight along +z of
      // the optical axis actually has world elevation +z * sin(pitch) and
      // horizontal distance +z * cos(pitch):
      //   y_world = y * cos(pitch) + z * sin(pitch)
      //   z_horiz = -y * sin(pitch) + z * cos(pitch)
      final cp = math.cos(pitchRadians);
      final sp = math.sin(pitchRadians);
      final yw = cp * y + sp * z;
      final zw = -sp * y + cp * z;
      y = yw;
      z = zw;
    }

    return Vector3(x, y, z);
  }

  static double _medianSorted(List<double> sorted) {
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : 0.5 * (sorted[mid - 1] + sorted[mid]);
  }

  static ({List<double> values, List<List<double>> vectors}) _jacobiSymmetric3x3(
    List<List<double>> input,
  ) {
    final a = List<List<double>>.generate(
      3,
      (i) => List<double>.from(input[i]),
    );
    final v = List<List<double>>.generate(
      3,
      (i) => List<double>.generate(3, (j) => i == j ? 1.0 : 0.0),
    );

    for (var iter = 0; iter < 48; iter++) {
      var p = 0;
      var q = 1;
      var maxOff = a[0][1].abs();
      for (var i = 0; i < 3; i++) {
        for (var j = i + 1; j < 3; j++) {
          final mag = a[i][j].abs();
          if (mag > maxOff) {
            maxOff = mag;
            p = i;
            q = j;
          }
        }
      }
      if (maxOff < 1e-15) break;

      final diff = a[q][q] - a[p][p];
      final double t;
      if (diff.abs() < 1e-30) {
        t = 1.0;
      } else {
        final tau = diff / (2.0 * a[p][q]);
        t = tau >= 0.0
            ? 1.0 / (tau + math.sqrt(1.0 + tau * tau))
            : -1.0 / (-tau + math.sqrt(1.0 + tau * tau));
      }
      final c = 1.0 / math.sqrt(1.0 + t * t);
      final s = t * c;

      final app = a[p][p];
      final aqq = a[q][q];
      final apq = a[p][q];
      a[p][p] = app - t * apq;
      a[q][q] = aqq + t * apq;
      a[p][q] = 0.0;
      a[q][p] = 0.0;

      for (var k = 0; k < 3; k++) {
        if (k != p && k != q) {
          final akp = a[k][p];
          final akq = a[k][q];
          a[k][p] = a[p][k] = c * akp - s * akq;
          a[k][q] = a[q][k] = s * akp + c * akq;
        }
        final vkp = v[k][p];
        final vkq = v[k][q];
        v[k][p] = c * vkp - s * vkq;
        v[k][q] = s * vkp + c * vkq;
      }
    }

    return (
      values: <double>[a[0][0], a[1][1], a[2][2]],
      vectors: v,
    );
  }
}
