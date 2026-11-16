import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Result of evaluating a raw 3D landmark sample against a causal kinematic
/// velocity threshold.
class SpikeGatedSample3D {
  const SpikeGatedSample3D({
    required this.position,
    required this.isHeldBySpikeGate,
    required this.rejectedStreak,
  });

  /// Accepted position, or the last accepted reference position if rejected.
  final Vector3 position;

  /// True when the raw observation exceeded [VelocitySpikeGate3D.maxSpeedMetersPerSec]
  /// and was substituted with the previous accepted position.
  final bool isHeldBySpikeGate;

  /// Number of consecutive frames rejected by the spike gate.
  final int rejectedStreak;
}

/// Causal velocity-based outlier gate that prevents single-frame 2D detector
/// swaps (e.g., left/right wrist flip or background false positive) from
/// teleporting a 3D landmark or contaminating downstream smoothing filters.
///
/// Includes a configurable [maxConsecutiveRejections] staleness recovery limit
/// so legitimate rapid relocations never cause permanent lockout.
class VelocitySpikeGate3D {
  VelocitySpikeGate3D({
    this.maxSpeedMetersPerSec = 7.5,
    this.maxConsecutiveRejections = 6,
  }) : assert(maxSpeedMetersPerSec > 0),
       assert(maxConsecutiveRejections >= 1);

  final double maxSpeedMetersPerSec;
  final int maxConsecutiveRejections;

  Vector3? _acceptedPosition;
  int _rejectedStreak = 0;

  Vector3? get lastAcceptedPosition => _acceptedPosition?.clone();
  int get rejectedStreak => _rejectedStreak;

  /// Evaluates [rawPosition] across elapsed [dtSeconds] (`> 0`).
  SpikeGatedSample3D evaluate(Vector3 rawPosition, double dtSeconds) {
    if (!rawPosition.x.isFinite ||
        !rawPosition.y.isFinite ||
        !rawPosition.z.isFinite) {
      final fallback = _acceptedPosition?.clone() ?? Vector3.zero();
      return SpikeGatedSample3D(
        position: fallback,
        isHeldBySpikeGate: true,
        rejectedStreak: ++_rejectedStreak,
      );
    }

    if (_acceptedPosition == null || _rejectedStreak >= maxConsecutiveRejections) {
      _acceptedPosition = rawPosition.clone();
      _rejectedStreak = 0;
      return SpikeGatedSample3D(
        position: rawPosition.clone(),
        isHeldBySpikeGate: false,
        rejectedStreak: 0,
      );
    }

    final safeDt = math.max(1e-4, dtSeconds);
    final speed = rawPosition.distanceTo(_acceptedPosition!) / safeDt;
    if (speed <= maxSpeedMetersPerSec) {
      _acceptedPosition = rawPosition.clone();
      _rejectedStreak = 0;
      return SpikeGatedSample3D(
        position: rawPosition.clone(),
        isHeldBySpikeGate: false,
        rejectedStreak: 0,
      );
    }

    _rejectedStreak++;
    return SpikeGatedSample3D(
      position: _acceptedPosition!.clone(),
      isHeldBySpikeGate: true,
      rejectedStreak: _rejectedStreak,
    );
  }

  /// Forces the gate reference directly to [position] (e.g., on fiducial PnP lock).
  void snapTo(Vector3 position) {
    _acceptedPosition = position.clone();
    _rejectedStreak = 0;
  }

  void reset() {
    _acceptedPosition = null;
    _rejectedStreak = 0;
  }
}

/// Stabilized 3D landmark state for one frame, carrying explicit measurement
/// provenance so online calibrators (anthropometry, IPD, bone lengths) can
/// exclude extrapolated or spike-held samples.
class StabilizedLandmark3D {
  const StabilizedLandmark3D({
    required this.position,
    required this.velocity,
    required this.isPredicted,
    required this.isHeldBySpikeGate,
    required this.extrapolationFrameCount,
  });

  final Vector3 position;
  final Vector3 velocity;

  /// True when the raw observation was absent this frame and [position] was
  /// extrapolated from damped velocity.
  final bool isPredicted;

  /// True when the raw observation jumped faster than physically plausible and
  /// was held at the last accepted coordinate.
  final bool isHeldBySpikeGate;

  /// Consecutive frames since a real observation was seen (`0` when observed).
  final int extrapolationFrameCount;

  /// True if and only if [position] comes from a real, accepted observation
  /// this frame — safe to feed into online anthropometric / scale estimators.
  bool get isMeasuredObservation => !isPredicted && !isHeldBySpikeGate;
}

/// Causal 3D landmark stabilizer combining:
/// 1. [VelocitySpikeGate3D] teleportation rejection,
/// 2. Adaptive-cutoff 1-Euro filtering (Casiez, Roussel & Vogel, CHI 2012), and
/// 3. Short-horizon damped-velocity gap extrapolation across brief occlusions.
class CausalLandmarkStabilizer3D {
  CausalLandmarkStabilizer3D({
    this.minCutoffHz = 1.35,
    this.beta = 0.28,
    this.derivativeCutoffHz = 1.20,
    double maxSpeedMetersPerSec = 7.5,
    int maxConsecutiveRejections = 6,
    this.maxExtrapolationFrames = 3,
    this.velocityDecayPerFrame = 0.50,
  }) : assert(minCutoffHz > 0),
       assert(beta >= 0),
       assert(derivativeCutoffHz > 0),
       assert(maxExtrapolationFrames >= 0),
       assert(velocityDecayPerFrame >= 0 && velocityDecayPerFrame <= 1.0),
       _spikeGate = VelocitySpikeGate3D(
         maxSpeedMetersPerSec: maxSpeedMetersPerSec,
         maxConsecutiveRejections: maxConsecutiveRejections,
       );

  final double minCutoffHz;
  final double beta;
  final double derivativeCutoffHz;
  final int maxExtrapolationFrames;
  final double velocityDecayPerFrame;

  final VelocitySpikeGate3D _spikeGate;

  Vector3? _xHat;
  Vector3 _dxHat = Vector3.zero();
  int _extrapolatedFrames = 0;

  bool get isInitialized => _xHat != null;
  Vector3? get currentPosition => _xHat?.clone();
  Vector3 get currentVelocity => _dxHat.clone();

  /// Updates the stabilizer with a newly observed [rawObservation] over [dtSeconds].
  StabilizedLandmark3D updateObserved(Vector3 rawObservation, double dtSeconds) {
    final safeDt = dtSeconds.clamp(1e-4, 0.5);
    final gated = _spikeGate.evaluate(rawObservation, safeDt);

    if (_xHat == null) {
      _xHat = gated.position.clone();
      _dxHat = Vector3.zero();
      _extrapolatedFrames = 0;
      return StabilizedLandmark3D(
        position: _xHat!.clone(),
        velocity: Vector3.zero(),
        isPredicted: false,
        isHeldBySpikeGate: gated.isHeldBySpikeGate,
        extrapolationFrameCount: 0,
      );
    }

    if (gated.isHeldBySpikeGate) {
      // Decay velocity while holding against a single-frame spike so we never
      // inject synthetic momentum from the rejected jump.
      _dxHat.scale(velocityDecayPerFrame);
      return StabilizedLandmark3D(
        position: _xHat!.clone(),
        velocity: _dxHat.clone(),
        isPredicted: false,
        isHeldBySpikeGate: true,
        extrapolationFrameCount: 0,
      );
    }

    final rawDx = (gated.position - _xHat!) / safeDt;
    final alphaD = _smoothingFactor(derivativeCutoffHz, safeDt);
    _dxHat = _dxHat + (rawDx - _dxHat) * alphaD;

    final speed = _dxHat.length;
    final adaptiveCutoff = minCutoffHz + beta * speed;
    final alphaX = _smoothingFactor(adaptiveCutoff, safeDt);
    _xHat = _xHat! + (gated.position - _xHat!) * alphaX;
    _extrapolatedFrames = 0;

    return StabilizedLandmark3D(
      position: _xHat!.clone(),
      velocity: _dxHat.clone(),
      isPredicted: false,
      isHeldBySpikeGate: false,
      extrapolationFrameCount: 0,
    );
  }

  /// Advances the stabilizer when no valid detection arrived this frame.
  ///
  /// Returns a damped-velocity prediction for up to [maxExtrapolationFrames]
  /// consecutive missing frames (`isPredicted: true`), or `null` once the
  /// short prediction horizon expires.
  StabilizedLandmark3D? updateMissing(double dtSeconds) {
    if (_xHat == null || _extrapolatedFrames >= maxExtrapolationFrames) {
      return null;
    }
    final safeDt = dtSeconds.clamp(1e-4, 0.25);
    _extrapolatedFrames++;
    _dxHat.scale(velocityDecayPerFrame);
    _xHat = _xHat! + _dxHat * safeDt;
    _spikeGate.snapTo(_xHat!);
    return StabilizedLandmark3D(
      position: _xHat!.clone(),
      velocity: _dxHat.clone(),
      isPredicted: true,
      isHeldBySpikeGate: false,
      extrapolationFrameCount: _extrapolatedFrames,
    );
  }

  /// Immediately anchors the filter state to [exactPosition] (e.g., on initial
  /// high-precision fiducial PnP acquisition).
  StabilizedLandmark3D snapTo(Vector3 exactPosition) {
    _spikeGate.snapTo(exactPosition);
    _xHat = exactPosition.clone();
    _dxHat = Vector3.zero();
    _extrapolatedFrames = 0;
    return StabilizedLandmark3D(
      position: _xHat!.clone(),
      velocity: Vector3.zero(),
      isPredicted: false,
      isHeldBySpikeGate: false,
      extrapolationFrameCount: 0,
    );
  }

  void reset() {
    _spikeGate.reset();
    _xHat = null;
    _dxHat = Vector3.zero();
    _extrapolatedFrames = 0;
  }

  static double _smoothingFactor(double cutoffHz, double dtSeconds) {
    final tau = 1.0 / (2.0 * math.pi * cutoffHz);
    return 1.0 / (1.0 + tau / dtSeconds);
  }
}
