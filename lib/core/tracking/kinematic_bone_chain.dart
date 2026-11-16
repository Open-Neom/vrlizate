import 'dart:collection';
import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Robust statistical summary of a skeletal bone segment over a rolling window.
class BoneSegmentStats {
  const BoneSegmentStats({
    required this.boneKey,
    required this.medianLengthMeters,
    required this.madMeters,
    required this.sampleCount,
    required this.usedSeedFallback,
  });

  /// Directed key `"parent->child"`.
  final String boneKey;

  /// Median length in meters across the active rolling window (or anthropometric seed).
  final double medianLengthMeters;

  /// Median Absolute Deviation (`median(|L_i - median(L)|)`) in meters.
  final double madMeters;

  /// Number of real (non-extrapolated) observations inside the window.
  final int sampleCount;

  /// True when no real samples were available and the anthropometric seed was returned.
  final bool usedSeedFallback;

  /// Gaussian-consistent robust coefficient of variation (`1.4826 * MAD / median`),
  /// resilient to transient foreshortening or partial occlusion frames.
  double get robustTemporalCv => medianLengthMeters > 1e-6
      ? (1.4826 * madMeters) / medianLengthMeters
      : double.infinity;
}

/// Online rolling-window median bone-length estimator seeded from biomechanical
/// anthropometry (Winter 2009).
///
/// Only genuinely measured endpoints (`measuredJoints`) should be passed to
/// [recordMeasuredFrame] so extrapolated gap-fill frames never reinforce their
/// own synthetic bone lengths.
class RollingMedianBoneEstimator {
  RollingMedianBoneEstimator({
    required Map<String, double> seedLengthsMeters,
    this.windowSeconds = 10.0,
    this.maxSamplesPerBone = 240,
  }) : assert(windowSeconds > 0),
       assert(maxSamplesPerBone >= 8),
       _seeds = Map<String, double>.unmodifiable(seedLengthsMeters) {
    for (final entry in _seeds.entries) {
      final sep = entry.key.indexOf('->');
      if (sep <= 0 || sep >= entry.key.length - 2 || entry.value <= 0) {
        throw ArgumentError.value(
          entry.key,
          'seedLengthsMeters',
          'Bone keys must follow "parent->child" with positive seed length.',
        );
      }
      _endpoints[entry.key] = (
        parent: entry.key.substring(0, sep),
        child: entry.key.substring(sep + 2),
      );
      _windows[entry.key] = ListQueue<({double tSec, double lengthM})>();
    }
  }

  final Map<String, double> _seeds;
  final double windowSeconds;
  final int maxSamplesPerBone;

  final Map<String, ({String parent, String child})> _endpoints = {};
  final Map<String, ListQueue<({double tSec, double lengthM})>> _windows = {};

  /// Records a frame of **real** 3D joint observations at monotonic [timeSeconds]
  /// and evicts samples older than `timeSeconds - windowSeconds`.
  void recordMeasuredFrame(
    Map<String, Vector3> measuredJoints, {
    required double timeSeconds,
  }) {
    final cutoff = timeSeconds - windowSeconds;
    for (final entry in _endpoints.entries) {
      final boneKey = entry.key;
      final q = _windows[boneKey]!;
      while (q.isNotEmpty && q.first.tSec < cutoff) {
        q.removeFirst();
      }

      final p = measuredJoints[entry.value.parent];
      final c = measuredJoints[entry.value.child];
      if (p != null && c != null) {
        final dist = p.distanceTo(c);
        if (dist.isFinite && dist > 1e-4) {
          q.addLast((tSec: timeSeconds, lengthM: dist));
          while (q.length > maxSamplesPerBone) {
            q.removeFirst();
          }
        }
      }
    }
  }

  /// Current median length (meters) for [boneKey], or its anthropometric seed
  /// if the rolling window is empty.
  double lengthFor(String boneKey) => statsFor(boneKey).medianLengthMeters;

  /// Snapshot of all current bone lengths (`"parent->child" -> meters`).
  Map<String, double> get currentLengths => <String, double>{
    for (final key in _seeds.keys) key: lengthFor(key),
  };

  /// Computes robust median and MAD statistics for [boneKey].
  BoneSegmentStats statsFor(String boneKey) {
    final seed = _seeds[boneKey];
    if (seed == null) {
      throw ArgumentError.value(boneKey, 'boneKey', 'Unknown bone key.');
    }
    final q = _windows[boneKey]!;
    if (q.isEmpty) {
      return BoneSegmentStats(
        boneKey: boneKey,
        medianLengthMeters: seed,
        madMeters: 0.0,
        sampleCount: 0,
        usedSeedFallback: true,
      );
    }

    final values = <double>[for (final s in q) s.lengthM]..sort();
    final med = _sortedMedian(values);
    final absDevs = <double>[for (final v in values) (v - med).abs()]..sort();
    final mad = _sortedMedian(absDevs);

    return BoneSegmentStats(
      boneKey: boneKey,
      medianLengthMeters: med,
      madMeters: mad,
      sampleCount: values.length,
      usedSeedFallback: false,
    );
  }

  /// Evaluates whether tracked limb segments remain temporally rigid
  /// (`robustTemporalCv <= maxRobustCv`) and bilaterally symmetric
  /// (`|L - R| / mean <= maxAsymmetryRatio`).
  bool isAnatomicallyConsistent({
    List<(String, String)> symmetricPairs = const [],
    double maxRobustCv = 0.16,
    double maxAsymmetryRatio = 0.16,
    int minSamplesForCheck = 5,
  }) {
    for (final key in _seeds.keys) {
      final st = statsFor(key);
      if (st.sampleCount >= minSamplesForCheck &&
          st.robustTemporalCv > maxRobustCv) {
        return false;
      }
    }
    for (final (leftKey, rightKey) in symmetricPairs) {
      if (!_seeds.containsKey(leftKey) || !_seeds.containsKey(rightKey)) {
        continue;
      }
      final ls = statsFor(leftKey);
      final rs = statsFor(rightKey);
      if (ls.sampleCount < minSamplesForCheck ||
          rs.sampleCount < minSamplesForCheck) {
        continue;
      }
      final mean = 0.5 * (ls.medianLengthMeters + rs.medianLengthMeters);
      if (mean > 1e-5 &&
          (ls.medianLengthMeters - rs.medianLengthMeters).abs() / mean >
              maxAsymmetryRatio) {
        return false;
      }
    }
    return true;
  }

  void reset() {
    for (final q in _windows.values) {
      q.clear();
    }
  }

  static double _sortedMedian(List<double> sorted) {
    final n = sorted.length;
    final mid = n ~/ 2;
    if (n.isOdd) return sorted[mid];
    return 0.5 * (sorted[mid - 1] + sorted[mid]);
  }
}

/// Closed-form breadth-first skeletal tree rigidifier.
///
/// Anchors every observed root joint at its measured 3D coordinate, traverses
/// children in topological order, and places each child along the unit vector
/// from the **already-corrected** parent toward the observed child at the exact
/// enforced bone length. Retains the last valid unit bone direction so a child
/// that drops out briefly extends along its prior anatomical orientation rather
/// than collapsing onto its parent.
class ForwardKinematicChainRigidifier {
  ForwardKinematicChainRigidifier({
    required Map<String, List<String>> jointHierarchy,
    Vector3? defaultFallbackDirection,
  }) : _fallbackDirection =
           (defaultFallbackDirection ?? Vector3(0.0, -1.0, 0.0)).normalized() {
    final allChildren = <String>{
      for (final children in jointHierarchy.values) ...children,
    };
    final roots = <String>[
      for (final parent in jointHierarchy.keys)
        if (!allChildren.contains(parent)) parent,
    ];

    final edges = <({String parent, String child, String boneKey})>[];
    final visited = <String>{...roots};
    final queue = ListQueue<String>.of(roots);
    while (queue.isNotEmpty) {
      final parent = queue.removeFirst();
      final children = jointHierarchy[parent];
      if (children == null) continue;
      for (final child in children) {
        edges.add((
          parent: parent,
          child: child,
          boneKey: '$parent->$child',
        ));
        if (visited.add(child)) {
          queue.addLast(child);
        }
      }
    }

    _roots = List<String>.unmodifiable(roots);
    _edges = List<({String parent, String child, String boneKey})>.unmodifiable(
      edges,
    );
  }

  late final List<String> _roots;
  late final List<({String parent, String child, String boneKey})> _edges;
  final Vector3 _fallbackDirection;
  final Map<String, Vector3> _lastValidDirection = {};

  /// Enforces [boneLengthsMeters] (`"parent->child" -> meters`) over [observedJoints].
  Map<String, Vector3> rigidify(
    Map<String, Vector3> observedJoints,
    Map<String, double> boneLengthsMeters,
  ) {
    final corrected = <String, Vector3>{};
    for (final root in _roots) {
      final rootPos = observedJoints[root];
      if (rootPos != null) {
        corrected[root] = rootPos.clone();
      }
    }

    for (final edge in _edges) {
      final parentPos = corrected[edge.parent];
      if (parentPos == null) continue;
      final length = boneLengthsMeters[edge.boneKey];
      if (length == null || !length.isFinite || length <= 0.0) continue;

      Vector3? unitDir;
      final childObs = observedJoints[edge.child];
      if (childObs != null) {
        final delta = childObs - parentPos;
        final norm = delta.length;
        if (norm.isFinite && norm > 1e-6) {
          unitDir = delta / norm;
          _lastValidDirection[edge.boneKey] = unitDir.clone();
        }
      }
      unitDir ??= _lastValidDirection[edge.boneKey] ?? _fallbackDirection;
      corrected[edge.child] = parentPos + unitDir * length;
    }

    return corrected;
  }

  void reset() {
    _lastValidDirection.clear();
  }
}

/// Standard anthropometric limb ratios as fractions of total standing stature
/// (Winter 2009 / Drillis & Contini 1966).
abstract final class VrAnthropometricSegmentRatios {
  static const double biacromialShoulderWidth = 0.259;
  static const double upperArm = 0.186;
  static const double forearm = 0.146;
  static const double handLength = 0.108;
  static const double thigh = 0.245;
  static const double shank = 0.285;

  /// Builds upper-body seed lengths (`meters`) scaled to [statureMeters].
  static Map<String, double> buildUpperBodySeeds(double statureMeters) {
    final h = math.max(1.0, statureMeters);
    return <String, double>{
      'left_shoulder->left_elbow': h * upperArm,
      'left_elbow->left_wrist': h * forearm,
      'right_shoulder->right_elbow': h * upperArm,
      'right_elbow->right_wrist': h * forearm,
    };
  }
}
