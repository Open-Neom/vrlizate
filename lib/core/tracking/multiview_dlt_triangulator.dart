import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Eight-parameter pinhole + Brown–Conrady radial/tangential lens model
/// (`fx, fy, cx, cy, k1, k2, p1, p2`).
///
/// Undistorts sparse 2D keypoints via exact `2x2` analytical Newton–Raphson
/// iterations (`< 0.02 ms` per frame in pure Dart) rather than warping full
/// camera image buffers.
class CameraDistortionIntrinsics {
  const CameraDistortionIntrinsics({
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    this.k1 = 0.0,
    this.k2 = 0.0,
    this.p1 = 0.0,
    this.p2 = 0.0,
  }) : assert(fx > 0),
       assert(fy > 0);

  factory CameraDistortionIntrinsics.fromHorizontalFov({
    required int widthPx,
    required int heightPx,
    required double horizontalFovDegrees,
    double k1 = 0.0,
    double k2 = 0.0,
    double p1 = 0.0,
    double p2 = 0.0,
  }) {
    final halfTanX = math.tan((horizontalFovDegrees * math.pi / 180.0) * 0.5);
    final focal = (widthPx * 0.5) / halfTanX;
    return CameraDistortionIntrinsics(
      fx: focal,
      fy: focal,
      cx: widthPx * 0.5,
      cy: heightPx * 0.5,
      k1: k1,
      k2: k2,
      p1: p1,
      p2: p2,
    );
  }

  final double fx;
  final double fy;
  final double cx;
  final double cy;
  final double k1;
  final double k2;
  final double p1;
  final double p2;

  bool get hasDistortion =>
      k1 != 0.0 || k2 != 0.0 || p1 != 0.0 || p2 != 0.0;

  /// Projects a 3D point in CV camera coordinates (`+X` right, `+Y` down,
  /// `+Z` forward) into distorted pixel coordinates `(u_px, v_px)`.
  Vector2 projectCameraPoint(Vector3 pointCamera) {
    final invZ = 1.0 / pointCamera.z;
    final x = pointCamera.x * invZ;
    final y = pointCamera.y * invZ;
    if (!hasDistortion) {
      return Vector2(fx * x + cx, fy * y + cy);
    }
    final r2 = x * x + y * y;
    final radial = 1.0 + k1 * r2 + k2 * r2 * r2;
    final xd = x * radial + 2.0 * p1 * x * y + p2 * (r2 + 2.0 * x * x);
    final yd = y * radial + p1 * (r2 + 2.0 * y * y) + 2.0 * p2 * x * y;
    return Vector2(fx * xd + cx, fy * yd + cy);
  }

  /// Converts a distorted pixel observation `(px, py)` into undistorted
  /// normalized pinhole coordinates `(x_n, y_n)` on the `Z = 1` plane.
  Vector2 undistortPixelToNormalized(
    double px,
    double py, {
    int maxIterations = 6,
  }) {
    final xd = (px - cx) / fx;
    final yd = (py - cy) / fy;
    if (!hasDistortion) {
      return Vector2(xd, yd);
    }

    var x = xd;
    var y = yd;
    for (var iter = 0; iter < maxIterations; iter++) {
      final r2 = x * x + y * y;
      final radial = 1.0 + k1 * r2 + k2 * r2 * r2;
      final fxVal = x * radial + 2.0 * p1 * x * y + p2 * (r2 + 2.0 * x * x) - xd;
      final fyVal = y * radial + p1 * (r2 + 2.0 * y * y) + 2.0 * p2 * x * y - yd;
      if (fxVal * fxVal + fyVal * fyVal < 1e-22) break;

      final s = k1 + 2.0 * k2 * r2;
      final j00 = radial + 2.0 * x * x * s + 2.0 * p1 * y + 6.0 * p2 * x;
      final j01 = 2.0 * x * y * s + 2.0 * p1 * x + 2.0 * p2 * y;
      final j11 = radial + 2.0 * y * y * s + 6.0 * p1 * y + 2.0 * p2 * x;
      final det = j00 * j11 - j01 * j01;
      if (!det.isFinite || det.abs() < 1e-12) break;

      final invDet = 1.0 / det;
      x -= (j11 * fxVal - j01 * fyVal) * invDet;
      y -= (-j01 * fxVal + j00 * fyVal) * invDet;
    }
    return Vector2(x, y);
  }

  /// Undistorts a normalized `[0..1]` image coordinate back into an equivalent
  /// ideal pinhole `[0..1]` coordinate for the given frame dimensions.
  Vector2 undistortUv(double u, double v, int widthPx, int heightPx) {
    if (!hasDistortion) return Vector2(u, v);
    final norm = undistortPixelToNormalized(u * widthPx, v * heightPx);
    final pu = (fx * norm.x + cx) / widthPx;
    final pv = (fy * norm.y + cy) / heightPx;
    return Vector2(pu, pv);
  }
}

/// Extrinsic + intrinsic specification of one calibrated camera view:
/// `p_cam = worldToCameraRotation * p_world + worldToCameraTranslation`.
class CalibratedCameraView {
  CalibratedCameraView({
    required this.id,
    required this.intrinsics,
    required Matrix3 worldToCameraRotation,
    required Vector3 worldToCameraTranslation,
  }) : worldToCameraRotation = worldToCameraRotation.clone(),
       worldToCameraTranslation = worldToCameraTranslation.clone();

  final String id;
  final CameraDistortionIntrinsics intrinsics;
  final Matrix3 worldToCameraRotation;
  final Vector3 worldToCameraTranslation;

  Vector3 worldToCamera(Vector3 worldPoint) =>
      worldToCameraRotation.transformed(worldPoint) + worldToCameraTranslation;

  Vector2 projectWorldToPixel(Vector3 worldPoint) =>
      intrinsics.projectCameraPoint(worldToCamera(worldPoint));
}

/// Output of [MultiViewDltTriangulator.triangulatePixels].
class MultiViewTriangulationResult {
  const MultiViewTriangulationResult({
    required this.pointWorld,
    required this.meanNormalizedReprojectionError,
    required this.perCameraWeights,
    required this.inlierCameraCount,
  });

  final Vector3 pointWorld;
  final double meanNormalizedReprojectionError;

  /// Normalized consensus weights (`0..1`) indicating each camera's agreement.
  /// Occluded or mis-detected views receive near-zero weight when `N >= 3`.
  final Map<String, double> perCameraWeights;
  final int inlierCameraCount;
}

/// Pure-Dart multi-camera (`N >= 2`) Direct Linear Transform (`DLT`) 3D
/// triangulator (Hartley & Zisserman 2004, Ch. 12) with subset-consensus
/// outlier rejection for occluded views when `N >= 3`.
class MultiViewDltTriangulator {
  MultiViewDltTriangulator({
    required List<CalibratedCameraView> cameras,
    this.targetNormalizedReprojectionError = 0.012,
    this.minimumCameras = 2,
    this.maxCamerasToDrop = 1,
  }) : assert(cameras.length >= 2),
       assert(minimumCameras >= 2),
       _camerasById = <String, CalibratedCameraView>{
         for (final cam in cameras) cam.id: cam,
       };

  final Map<String, CalibratedCameraView> _camerasById;
  final double targetNormalizedReprojectionError;
  final int minimumCameras;
  final int maxCamerasToDrop;

  List<String> get cameraIds => _camerasById.keys.toList(growable: false);

  /// Triangulates a single 3D world point from pixel observations `(px, py)`
  /// keyed by camera ID. Returns `null` if fewer than [minimumCameras] valid
  /// observations exist or cheirality (`Z_cam > 0`) fails.
  MultiViewTriangulationResult? triangulatePixels(
    Map<String, Vector2> pixelObservationsByCamera, {
    bool enableOutlierRejection = true,
  }) {
    final activeViews = <CalibratedCameraView>[];
    final undistortedPts = <Vector2>[];

    for (final entry in pixelObservationsByCamera.entries) {
      final cam = _camerasById[entry.key];
      final px = entry.value;
      if (cam == null || !px.x.isFinite || !px.y.isFinite) continue;
      activeViews.add(cam);
      undistortedPts.add(
        cam.intrinsics.undistortPixelToNormalized(px.x, px.y),
      );
    }

    final n = activeViews.length;
    if (n < minimumCameras) return null;

    final baselinePt = _solveDltHomogeneous(activeViews, undistortedPts);
    if (baselinePt == null) return null;

    final baselineErr = _meanNormalizedError(
      baselinePt,
      activeViews,
      undistortedPts,
    );
    if (!baselineErr.isFinite) return null;

    if (!enableOutlierRejection ||
        n <= minimumCameras ||
        baselineErr <= targetNormalizedReprojectionError) {
      return MultiViewTriangulationResult(
        pointWorld: baselinePt,
        meanNormalizedReprojectionError: baselineErr,
        perCameraWeights: <String, double>{
          for (final v in activeViews) v.id: 1.0,
        },
        inlierCameraCount: n,
      );
    }

    // Progressive subset-consensus outlier rejection for N >= 3 cameras:
    // evaluates subsets dropping 1..maxCamerasToDrop views to locate the
    // minimum-residual consensus hypothesis, then scores every camera's
    // individual reprojection residual against that consensus 3D point.
    final target = math.max(1e-5, targetNormalizedReprojectionError);
    final candidates = <({Vector3 point, double err, List<int> indices})>[
      (
        point: baselinePt,
        err: baselineErr,
        indices: List<int>.generate(n, (i) => i),
      ),
    ];

    var bestPt = baselinePt;
    var bestErr = baselineErr;
    var bestSubsetIndices = candidates.first.indices;

    final allIndices = List<int>.generate(n, (i) => i);
    for (var drop = 1; drop <= maxCamerasToDrop; drop++) {
      final keepCount = n - drop;
      if (keepCount < minimumCameras) break;

      for (final combo in _combinations(allIndices, keepCount)) {
        final subViews = <CalibratedCameraView>[
          for (final idx in combo) activeViews[idx],
        ];
        final subPts = <Vector2>[
          for (final idx in combo) undistortedPts[idx],
        ];
        final candidate = _solveDltHomogeneous(subViews, subPts);
        if (candidate == null) continue;
        final err = _meanNormalizedError(candidate, subViews, subPts);
        if (!err.isFinite) continue;

        candidates.add((point: candidate, err: err, indices: combo));
        if (err < bestErr) {
          bestErr = err;
          bestPt = candidate;
          bestSubsetIndices = combo;
        }
      }
      if (bestErr <= targetNormalizedReprojectionError) break;
    }

    if (bestErr >= baselineErr) {
      return MultiViewTriangulationResult(
        pointWorld: baselinePt,
        meanNormalizedReprojectionError: baselineErr,
        perCameraWeights: <String, double>{
          for (final v in activeViews) v.id: 1.0,
        },
        inlierCameraCount: n,
      );
    }

    final consensusBand = math.max(bestErr * 2.0, target * 0.15);
    final consensusSigma = math.max(bestErr * 1.25, target * 0.10);
    var weightedSum = Vector3.zero();
    var totalWeight = 0.0;
    for (final c in candidates) {
      if (c.err > consensusBand) continue;
      final ratio = c.err / consensusSigma;
      final w = math.exp(-0.5 * ratio * ratio);
      weightedSum += c.point * w;
      totalWeight += w;
    }

    var resolvedPt = totalWeight > 1e-12 ? (weightedSum / totalWeight) : bestPt;

    // Score each camera directly against resolvedPt and re-solve once over all
    // consensus inliers so all clean cameras contribute simultaneously.
    final weights = <String, double>{};
    final inlierViews = <CalibratedCameraView>[];
    final inlierPts = <Vector2>[];
    for (var i = 0; i < n; i++) {
      final camErr = _singleCameraNormalizedError(
        resolvedPt,
        activeViews[i],
        undistortedPts[i],
      );
      final w = camErr.isFinite
          ? math.exp(-0.5 * (camErr / target) * (camErr / target))
          : 0.0;
      weights[activeViews[i].id] = w.clamp(0.0, 1.0);
      if (camErr <= target * 1.5) {
        inlierViews.add(activeViews[i]);
        inlierPts.add(undistortedPts[i]);
      }
    }

    if (inlierViews.length >= minimumCameras) {
      final refined = _solveDltHomogeneous(inlierViews, inlierPts);
      if (refined != null) {
        final refinedErr = _meanNormalizedError(refined, inlierViews, inlierPts);
        if (refinedErr.isFinite && refinedErr <= bestErr * 1.25 + 1e-7) {
          resolvedPt = refined;
          bestErr = refinedErr;
        }
      }
    }

    return MultiViewTriangulationResult(
      pointWorld: resolvedPt,
      meanNormalizedReprojectionError: bestErr,
      perCameraWeights: weights,
      inlierCameraCount: inlierViews.length >= minimumCameras
          ? inlierViews.length
          : bestSubsetIndices.length,
    );
  }

  static Vector3? _solveDltHomogeneous(
    List<CalibratedCameraView> views,
    List<Vector2> normalizedPoints,
  ) {
    // Accumulate M = A^T * A (4x4 symmetric positive semi-definite) where each
    // camera contributes two normalized 4-rows:
    //   r_x = x * P_2 - P_0,  r_y = y * P_2 - P_1.
    final m = List<List<double>>.generate(
      4,
      (_) => List<double>.filled(4, 0.0),
    );

    for (var i = 0; i < views.length; i++) {
      final rot = views[i].worldToCameraRotation;
      final t = views[i].worldToCameraTranslation;
      final x = normalizedPoints[i].x;
      final y = normalizedPoints[i].y;

      final p00 = rot.entry(0, 0), p01 = rot.entry(0, 1), p02 = rot.entry(0, 2), p03 = t.x;
      final p10 = rot.entry(1, 0), p11 = rot.entry(1, 1), p12 = rot.entry(1, 2), p13 = t.y;
      final p20 = rot.entry(2, 0), p21 = rot.entry(2, 1), p22 = rot.entry(2, 2), p23 = t.z;

      _accumulateNormalizedRow(m, [
        x * p20 - p00,
        x * p21 - p01,
        x * p22 - p02,
        x * p23 - p03,
      ]);
      _accumulateNormalizedRow(m, [
        y * p20 - p10,
        y * p21 - p11,
        y * p22 - p12,
        y * p23 - p13,
      ]);
    }

    final eig = _jacobiSymmetric4x4(m);
    var minIdx = 0;
    for (var i = 1; i < 4; i++) {
      if (eig.values[i] < eig.values[minIdx]) minIdx = i;
    }

    final w = eig.vectors[3][minIdx];
    if (!w.isFinite || w.abs() < 1e-10) return null;
    final pt = Vector3(
      eig.vectors[0][minIdx] / w,
      eig.vectors[1][minIdx] / w,
      eig.vectors[2][minIdx] / w,
    );
    if (!pt.x.isFinite || !pt.y.isFinite || !pt.z.isFinite) return null;

    // Verify cheirality (point must lie in front of every participating camera).
    for (final cam in views) {
      if (cam.worldToCamera(pt).z <= 1e-4) return null;
    }
    return pt;
  }

  static void _accumulateNormalizedRow(List<List<double>> m, List<double> row) {
    final normSq =
        row[0] * row[0] + row[1] * row[1] + row[2] * row[2] + row[3] * row[3];
    if (!normSq.isFinite || normSq < 1e-18) return;
    final invNorm = 1.0 / math.sqrt(normSq);
    final r0 = row[0] * invNorm;
    final r1 = row[1] * invNorm;
    final r2 = row[2] * invNorm;
    final r3 = row[3] * invNorm;
    final r = <double>[r0, r1, r2, r3];
    for (var a = 0; a < 4; a++) {
      for (var b = 0; b < 4; b++) {
        m[a][b] += r[a] * r[b];
      }
    }
  }

  static double _singleCameraNormalizedError(
    Vector3 pointWorld,
    CalibratedCameraView view,
    Vector2 undistortedObs,
  ) {
    final pc = view.worldToCamera(pointWorld);
    if (pc.z <= 1e-5) return double.infinity;
    final dx = (pc.x / pc.z) - undistortedObs.x;
    final dy = (pc.y / pc.z) - undistortedObs.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _meanNormalizedError(
    Vector3 pointWorld,
    List<CalibratedCameraView> views,
    List<Vector2> undistortedObs,
  ) {
    var sum = 0.0;
    for (var i = 0; i < views.length; i++) {
      final err = _singleCameraNormalizedError(
        pointWorld,
        views[i],
        undistortedObs[i],
      );
      if (!err.isFinite) return double.infinity;
      sum += err;
    }
    return sum / views.length;
  }

  static Iterable<List<int>> _combinations(List<int> items, int k) sync* {
    if (k == 0) {
      yield const <int>[];
      return;
    }
    if (items.length < k) return;
    for (var i = 0; i <= items.length - k; i++) {
      final head = items[i];
      final tail = items.sublist(i + 1);
      for (final sub in _combinations(tail, k - 1)) {
        yield <int>[head, ...sub];
      }
    }
  }

  static ({List<double> values, List<List<double>> vectors}) _jacobiSymmetric4x4(
    List<List<double>> input,
  ) {
    final a = List<List<double>>.generate(
      4,
      (i) => List<double>.from(input[i]),
    );
    final v = List<List<double>>.generate(
      4,
      (i) => List<double>.generate(4, (j) => i == j ? 1.0 : 0.0),
    );

    for (var iter = 0; iter < 64; iter++) {
      var p = 0;
      var q = 1;
      var maxOff = a[0][1].abs();
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
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

      for (var k = 0; k < 4; k++) {
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
      values: <double>[a[0][0], a[1][1], a[2][2], a[3][3]],
      vectors: v,
    );
  }
}
