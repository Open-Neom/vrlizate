import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'controller_state.dart';
import 'hand_state.dart';
import 'vr_input_event_bus.dart';

/// Flexion state of an individual digit in the Cyberneom `eMudra` grammar.
///
/// Five digits with 3 states each yield `3^5 = 243` curl configurations per hand
/// before accounting for thumb-tip opposition, palm orientation, bimanual pairing,
/// and continuous analog trajectories.
enum VrDigitCurlState {
  extended('E'),
  arched('A'),
  folded('F');

  const VrDigitCurlState(this.symbol);
  final String symbol;
}

/// Thumb opposition / finger-pad contact channel for single-hand mudras.
enum VrThumbContactChannel {
  none('none'),
  indexTip('idx'), // Gyan / Chin
  middleTip('mid'), // Akash / Shuni
  ringTip('rng'), // Surya / Prithvi
  littleTip('lit'), // Buddhi / Varun
  palmCenter('plm'); // Adi

  const VrThumbContactChannel(this.symbol);
  final String symbol;
}

/// Quantized palm normal orientation relative to the viewer's local head frame.
enum VrPalmOrientationZone {
  forward('fwd'),
  towardSelf('self'),
  upwardSky('sky'),
  downwardEarth('earth'),
  inwardCenter('in'),
  outward('out');

  const VrPalmOrientationZone(this.symbol);
  final String symbol;
}

/// Camera viewpoint contributing to multi-view `eMudra` recognition.
enum VrEMudraCameraRole {
  /// Smartphone Visor rear camera (ideally `0.5x–0.6x` Ultra-Wide / `eyefish`).
  /// Strongest on dorsal finger spread, bimanual framing, and forward reach.
  visorUltraWide(
    id: 'visor_ultrawide',
    baseReliabilityWeight: 0.92,
    occlusionComplementaryBonus: 0.14,
  ),

  /// Smartphone Joystick camera looking upward from lap/chest height.
  /// Resolves palmar self-occlusion when fingers curl toward the user.
  joystickUpward(
    id: 'joystick_upward',
    baseReliabilityWeight: 0.84,
    occlusionComplementaryBonus: 0.18,
  ),

  /// PC Estación Faro webcam facing the user frontally (3rd-person view).
  /// Captures full bimanual span and hands outside the visor's optical frustum.
  desktopFaro(
    id: 'desktop_faro',
    baseReliabilityWeight: 0.88,
    occlusionComplementaryBonus: 0.16,
  );

  const VrEMudraCameraRole({
    required this.id,
    required this.baseReliabilityWeight,
    required this.occlusionComplementaryBonus,
  });

  final String id;
  final double baseReliabilityWeight;
  final double occlusionComplementaryBonus;
}

/// Canonical `eMudra` archetypes grounded in the Cyberneom / Open Neom
/// ontological interaction model (`cInd`, `fSa`, `beta`, `rhoNet`).
enum VrCanonicalEMudra {
  /// Neutral resting state — no mudra invoked.
  none,

  /// *Gyan eMudra* (Thumb + Index circle, remaining digits extended).
  /// Primary confirmation / selection (`ΔcInd` attentional lock).
  gyanConfirm,

  /// *Prana Telescopic eMudra* (Bimanual dual-pinch span OR sustained optical
  /// aperture frame). Continuously sweeps visor camera zoom (`0.6x .. 100x`).
  pranaTelescopeZoom,

  /// *El Dial de Sintonía* (Active pinch + axial wrist roll).
  /// Continuous analog parameter modulation (`-1.0 .. +1.0`).
  suryaTuningDial,

  /// *Estasis: Guardián del Tiempo* (Symmetric centered bimanual repose).
  /// Horizon recenter and sensory stabilization (`↓fSa`, `↓β`).
  dhyanaStasis,

  /// *Velo Abhaya* (Open vertical palm facing forward).
  /// Toggles / opens the real-world optical passthrough curtain (`Vista Real`).
  abhayaRealSight,

  /// *Akash / Verbo* (Thumb + Middle contact).
  /// Invokes `Itzli` / `SAIA` voice command channel or contextual world menu.
  akashInvoke,

  /// *El Telar Holográfico* (Full hand grasp / fist closure).
  /// Spatial object grab and 3D thread manipulation.
  telarWeaveGrab,

  /// Matches a user- or `.vrlw`-registered custom combinatorial signature.
  custom,
}

/// Logarithmic perceptual optical zoom curve spanning Ultra-Wide (`0.5x–0.6x`
/// `eyefish` ~120° FOV) up to extreme periscope telephoto (`100x` Space Zoom on
/// flagships such as Samsung Galaxy S25 Ultra).
abstract final class VrOpticalZoomCurve {
  /// Maps normalized gesture/slider progress [normalized01] (`0.0 .. 1.0`) to a
  /// physical zoom ratio in `[minZoom, maxZoom]` using logarithmic scaling so
  /// `0.6x → 1x → 3x → 10x → 30x → 100x` feels perceptually uniform.
  static double normalizedToZoomRatio(
    double normalized01, {
    required double minZoom,
    required double maxZoom,
  }) {
    final safeMin = math.max(0.1, minZoom);
    final safeMax = math.max(safeMin, maxZoom);
    if ((safeMax - safeMin).abs() < 1e-6) return safeMin;
    final t = normalized01.clamp(0.0, 1.0);
    return safeMin * math.pow(safeMax / safeMin, t).toDouble();
  }

  /// Inverse mapping from a physical [zoomRatio] back to `[0.0 .. 1.0]`.
  static double zoomRatioToNormalized(
    double zoomRatio, {
    required double minZoom,
    required double maxZoom,
  }) {
    final safeMin = math.max(0.1, minZoom);
    final safeMax = math.max(safeMin, maxZoom);
    if ((safeMax - safeMin).abs() < 1e-6) return 0.0;
    final clamped = zoomRatio.clamp(safeMin, safeMax);
    return (math.log(clamped / safeMin) / math.log(safeMax / safeMin)).clamp(
      0.0,
      1.0,
    );
  }

  /// Human-readable optical pipeline stage for HUDs and diagnostics.
  static String lensStageLabel(double zoomRatio, {double minZoom = 0.6}) {
    if (zoomRatio < 0.95) {
      return 'Ultra-Gran Angular / Eyefish (${zoomRatio.toStringAsFixed(1)}×)';
    }
    if (zoomRatio < 2.8) {
      return 'Gran Angular (${zoomRatio.toStringAsFixed(1)}×)';
    }
    if (zoomRatio < 9.5) {
      return 'Telefoto Óptico (${zoomRatio.toStringAsFixed(1)}×)';
    }
    if (zoomRatio < 29.5) {
      return 'Periscopio (${zoomRatio.toStringAsFixed(1)}×)';
    }
    return 'Space Zoom (${zoomRatio.toStringAsFixed(0)}×)';
  }
}

/// Topological + metric signature of a single hand used by [VrEMudraEngine].
class VrHandMudraSignature {
  const VrHandMudraSignature({
    required this.hand,
    required this.thumb,
    required this.index,
    required this.middle,
    required this.ring,
    required this.little,
    this.thumbContact = VrThumbContactChannel.none,
    this.palmZone = VrPalmOrientationZone.forward,
    this.thumbIndexApertureMeters = 0.06,
    this.wristRollRadians = 0.0,
    this.depthMeters = 0.48,
  });

  /// Extracts a full 5-digit signature from an OpenXR/MediaPipe 26-joint [HandState].
  factory VrHandMudraSignature.fromHandState(
    HandState state, {
    double defaultDepthMeters = 0.48,
  }) {
    final palm = state.palmPosition;
    if (!state.tracked || palm == null) {
      return VrHandMudraSignature(
        hand: state.hand,
        thumb: VrDigitCurlState.arched,
        index: VrDigitCurlState.arched,
        middle: VrDigitCurlState.arched,
        ring: VrDigitCurlState.arched,
        little: VrDigitCurlState.arched,
        depthMeters: defaultDepthMeters,
      );
    }

    VrDigitCurlState classifyTip(
      HandJoint tip, {
      double extendedMin = 0.072,
      double foldedMax = 0.046,
    }) {
      final p = state.joint(tip);
      if (p == null) return VrDigitCurlState.arched;
      final d = (p - palm).length;
      if (d >= extendedMin) return VrDigitCurlState.extended;
      if (d <= foldedMax) return VrDigitCurlState.folded;
      return VrDigitCurlState.arched;
    }

    final thumbPos = state.thumbTipPosition;
    final indexPos = state.indexTipPosition;
    final middlePos = state.joint(HandJoint.middleTip);
    final ringPos = state.joint(HandJoint.ringTip);
    final littlePos = state.joint(HandJoint.littleTip);

    var contact = VrThumbContactChannel.none;
    var bestContactDist = 0.026;
    if (thumbPos != null) {
      void check(Vector3? tipPos, VrThumbContactChannel ch) {
        if (tipPos == null) return;
        final d = (thumbPos - tipPos).length;
        if (d < bestContactDist) {
          bestContactDist = d;
          contact = ch;
        }
      }

      check(indexPos, VrThumbContactChannel.indexTip);
      check(middlePos, VrThumbContactChannel.middleTip);
      check(ringPos, VrThumbContactChannel.ringTip);
      check(littlePos, VrThumbContactChannel.littleTip);
      if (contact == VrThumbContactChannel.none &&
          (thumbPos - palm).length < 0.032) {
        contact = VrThumbContactChannel.palmCenter;
      }
    }

    final aperture = (thumbPos != null && indexPos != null)
        ? (thumbPos - indexPos).length
        : 0.06;

    // Estimate palm normal from wrist->middleMetacarpal and index->little axis.
    var palmZone = VrPalmOrientationZone.forward;
    var wristRoll = 0.0;
    final wrist = state.joint(HandJoint.wrist);
    final idxMcp = state.joint(HandJoint.indexProximal);
    final litMcp = state.joint(HandJoint.littleProximal);
    if (wrist != null && idxMcp != null && litMcp != null) {
      final across = (litMcp - idxMcp);
      final along = (palm - wrist);
      if (across.length2 > 1e-6 && along.length2 > 1e-6) {
        wristRoll = math.atan2(across.y, across.x);
        final rawNormal = state.hand == ControllerHand.right
            ? across.cross(along)
            : along.cross(across);
        if (rawNormal.length2 > 1e-6) {
          final n = rawNormal.normalized();
          if (n.y.abs() >= n.x.abs() && n.y.abs() >= n.z.abs()) {
            palmZone = n.y > 0
                ? VrPalmOrientationZone.upwardSky
                : VrPalmOrientationZone.downwardEarth;
          } else if (n.z.abs() >= n.x.abs()) {
            palmZone = n.z < 0
                ? VrPalmOrientationZone.forward
                : VrPalmOrientationZone.towardSelf;
          } else {
            final inward =
                (state.hand == ControllerHand.right && n.x < 0) ||
                (state.hand == ControllerHand.left && n.x > 0);
            palmZone = inward
                ? VrPalmOrientationZone.inwardCenter
                : VrPalmOrientationZone.outward;
          }
        }
      }
    }

    return VrHandMudraSignature(
      hand: state.hand,
      thumb: classifyTip(
        HandJoint.thumbTip,
        extendedMin: 0.056,
        foldedMax: 0.035,
      ),
      index: classifyTip(HandJoint.indexTip),
      middle: classifyTip(HandJoint.middleTip),
      ring: classifyTip(HandJoint.ringTip),
      little: classifyTip(HandJoint.littleTip, extendedMin: 0.064),
      thumbContact: contact,
      palmZone: palmZone,
      thumbIndexApertureMeters: aperture,
      wristRollRadians: wristRoll,
      depthMeters: palm.length > 0.05 ? palm.length : defaultDepthMeters,
    );
  }

  /// Lightweight constructor for coarse vision streams (e.g. Desktop Faro or
  /// low-power mobile detector providing pinch strength + 3D wrist/tip pose).
  factory VrHandMudraSignature.fromCoarsePose({
    required ControllerHand hand,
    required bool isPinching,
    bool isOpenPalm = false,
    bool isFist = false,
    double apertureMeters = 0.06,
    double wristRollRadians = 0.0,
    double depthMeters = 0.48,
  }) {
    if (isFist) {
      return VrHandMudraSignature(
        hand: hand,
        thumb: VrDigitCurlState.folded,
        index: VrDigitCurlState.folded,
        middle: VrDigitCurlState.folded,
        ring: VrDigitCurlState.folded,
        little: VrDigitCurlState.folded,
        thumbContact: VrThumbContactChannel.palmCenter,
        thumbIndexApertureMeters: 0.01,
        wristRollRadians: wristRollRadians,
        depthMeters: depthMeters,
      );
    }
    if (isPinching) {
      return VrHandMudraSignature(
        hand: hand,
        thumb: VrDigitCurlState.arched,
        index: VrDigitCurlState.arched,
        middle: VrDigitCurlState.extended,
        ring: VrDigitCurlState.extended,
        little: VrDigitCurlState.extended,
        thumbContact: VrThumbContactChannel.indexTip,
        thumbIndexApertureMeters: math.min(0.02, apertureMeters),
        wristRollRadians: wristRollRadians,
        depthMeters: depthMeters,
      );
    }
    if (isOpenPalm) {
      return VrHandMudraSignature(
        hand: hand,
        thumb: VrDigitCurlState.extended,
        index: VrDigitCurlState.extended,
        middle: VrDigitCurlState.extended,
        ring: VrDigitCurlState.extended,
        little: VrDigitCurlState.extended,
        palmZone: VrPalmOrientationZone.forward,
        thumbIndexApertureMeters: math.max(0.075, apertureMeters),
        wristRollRadians: wristRollRadians,
        depthMeters: depthMeters,
      );
    }
    return VrHandMudraSignature(
      hand: hand,
      thumb: VrDigitCurlState.arched,
      index: VrDigitCurlState.extended,
      middle: VrDigitCurlState.arched,
      ring: VrDigitCurlState.arched,
      little: VrDigitCurlState.arched,
      thumbIndexApertureMeters: apertureMeters,
      wristRollRadians: wristRollRadians,
      depthMeters: depthMeters,
    );
  }

  final ControllerHand hand;
  final VrDigitCurlState thumb;
  final VrDigitCurlState index;
  final VrDigitCurlState middle;
  final VrDigitCurlState ring;
  final VrDigitCurlState little;
  final VrThumbContactChannel thumbContact;
  final VrPalmOrientationZone palmZone;
  final double thumbIndexApertureMeters;
  final double wristRollRadians;
  final double depthMeters;

  /// Compact canonical topological descriptor (e.g. `R:A-A-E-E-E@idx:fwd`).
  String get code {
    final prefix = hand == ControllerHand.left ? 'L' : 'R';
    return '$prefix:${thumb.symbol}-${index.symbol}-${middle.symbol}-'
        '${ring.symbol}-${little.symbol}@${thumbContact.symbol}:${palmZone.symbol}';
  }

  bool get isGyanLike =>
      thumbContact == VrThumbContactChannel.indexTip &&
      middle == VrDigitCurlState.extended &&
      ring == VrDigitCurlState.extended;

  bool get isAkashLike =>
      thumbContact == VrThumbContactChannel.middleTip &&
      index == VrDigitCurlState.extended;

  bool get isAbhayaOpenPalm =>
      thumb == VrDigitCurlState.extended &&
      index == VrDigitCurlState.extended &&
      middle == VrDigitCurlState.extended &&
      ring == VrDigitCurlState.extended &&
      little == VrDigitCurlState.extended &&
      palmZone == VrPalmOrientationZone.forward;

  bool get isTelarFist =>
      index == VrDigitCurlState.folded &&
      middle == VrDigitCurlState.folded &&
      ring == VrDigitCurlState.folded &&
      little == VrDigitCurlState.folded;
}

/// Custom user- or `.vrlw`-defined `eMudra` pattern binding.
class VrCustomEMudraBinding {
  const VrCustomEMudraBinding({
    required this.id,
    required this.displayName,
    this.leftPatternCode,
    this.rightPatternCode,
    this.commandAction,
  });

  final String id;
  final String displayName;

  /// Optional topological code prefix/exact match for the left hand.
  final String? leftPatternCode;

  /// Optional topological code prefix/exact match for the right hand.
  final String? rightPatternCode;

  /// Optional semantic command dispatched to Cyberneom / Itzli / `.vrlw`.
  final String? commandAction;

  bool matches({VrHandMudraSignature? left, VrHandMudraSignature? right}) {
    if (leftPatternCode == null && rightPatternCode == null) return false;
    if (leftPatternCode != null) {
      if (left == null || !left.code.startsWith(leftPatternCode!)) return false;
    }
    if (rightPatternCode != null) {
      if (right == null || !right.code.startsWith(rightPatternCode!)) {
        return false;
      }
    }
    return true;
  }
}

/// Single-camera `eMudra` observation fed into [VrEMudraEngine].
class VrEMudraCameraObservation {
  const VrEMudraCameraObservation({
    required this.cameraRole,
    required this.confidence,
    this.leftHand,
    this.rightHand,
    this.bimanualSpanMeters,
    this.candidateOverride,
    this.timestampMicros = 0,
  });

  final VrEMudraCameraRole cameraRole;
  final double confidence;
  final VrHandMudraSignature? leftHand;
  final VrHandMudraSignature? rightHand;

  /// Distance between left and right hand centers in meters when both are visible.
  final double? bimanualSpanMeters;

  /// Optional direct classifier proposal from a dedicated gesture model.
  final VrCanonicalEMudra? candidateOverride;
  final int timestampMicros;
}

/// Fused multi-camera `eMudra` output produced by [VrEMudraEngine].
class VrEMudraFusionState {
  const VrEMudraFusionState({
    required this.activeMudra,
    required this.fusedConfidence,
    required this.normalizedZoom01,
    required this.targetZoomRatio,
    required this.dialValue,
    required this.dominantHandDepthMeters,
    required this.contributingCameras,
    this.customMudraId,
    this.activeSignatureCode = '',
  });

  static const VrEMudraFusionState idle = VrEMudraFusionState(
    activeMudra: VrCanonicalEMudra.none,
    fusedConfidence: 0.0,
    normalizedZoom01: 0.0,
    targetZoomRatio: 0.6,
    dialValue: 0.0,
    dominantHandDepthMeters: 0.50,
    contributingCameras: <VrEMudraCameraRole>{},
  );

  final VrCanonicalEMudra activeMudra;
  final String? customMudraId;

  /// Multi-camera fused confidence (`0.0 .. 1.0`).
  final double fusedConfidence;

  /// Smoothed normalized zoom control (`0.0` = Ultra-Wide `minZoom`,
  /// `1.0` = `maxZoom` such as `100x` on Galaxy S25 Ultra).
  final double normalizedZoom01;

  /// Physical zoom ratio computed via [VrOpticalZoomCurve].
  final double targetZoomRatio;

  /// Continuous dial value (`-1.0 .. +1.0`) for *El Dial de Sintonía*.
  final double dialValue;

  /// Metric distance of the active hand from the viewer (`meters`).
  final double dominantHandDepthMeters;

  /// Cameras currently contributing valid observations.
  final Set<VrEMudraCameraRole> contributingCameras;

  /// Canonical signature string for telemetry/debugging.
  final String activeSignatureCode;

  bool get isMultiCameraVerified => contributingCameras.length >= 2;
  bool get isTriCameraVerified => contributingCameras.length >= 3;

  /// Converts discrete `eMudra` activations into standard [VrInputEvent]s so
  /// any `.vrlz` or `.vrlw` experience can consume them out-of-the-box.
  VrInputEvent? toInputEvent() {
    switch (activeMudra) {
      case VrCanonicalEMudra.gyanConfirm:
        return VrInputEvent(
          type: VrInputType.select,
          source: VrInputSource.cameraHand,
          data: {
            'emudra': activeMudra.name,
            'confidence': fusedConfidence,
            'depthMeters': dominantHandDepthMeters,
          },
        );
      case VrCanonicalEMudra.dhyanaStasis:
        return VrInputEvent(
          type: VrInputType.recenter,
          source: VrInputSource.cameraHand,
          data: {'emudra': activeMudra.name, 'confidence': fusedConfidence},
        );
      case VrCanonicalEMudra.telarWeaveGrab:
        return VrInputEvent(
          type: VrInputType.grip,
          source: VrInputSource.cameraHand,
          data: {
            'emudra': activeMudra.name,
            'confidence': fusedConfidence,
            'depthMeters': dominantHandDepthMeters,
          },
        );
      case VrCanonicalEMudra.akashInvoke:
      case VrCanonicalEMudra.abhayaRealSight:
      case VrCanonicalEMudra.pranaTelescopeZoom:
      case VrCanonicalEMudra.suryaTuningDial:
      case VrCanonicalEMudra.custom:
        return VrInputEvent(
          type: VrInputType.buttonY,
          source: VrInputSource.cameraHand,
          data: {
            'emudra': customMudraId ?? activeMudra.name,
            'confidence': fusedConfidence,
            'zoomRatio': targetZoomRatio,
            'normalizedZoom': normalizedZoom01,
            'dialValue': dialValue,
            'cameras': contributingCameras.map((c) => c.id).toList(),
          },
        );
      case VrCanonicalEMudra.none:
        return null;
    }
  }
}

/// Multi-camera Cyberneom `eMudra` recognition and continuous optical-zoom
/// modulation engine.
///
/// Combines observations from up to three complementary viewpoints:
/// 1. [VrEMudraCameraRole.visorUltraWide] (Visor `0.5x–0.6x` Ultra-Wide),
/// 2. [VrEMudraCameraRole.joystickUpward] (Joystick upward camera), and
/// 3. [VrEMudraCameraRole.desktopFaro] (PC Estación Faro webcam).
class VrEMudraEngine {
  VrEMudraEngine({
    this.minConfidenceThreshold = 0.48,
    this.zoomSmoothingAlpha = 0.24,
    this.activationConfirmFrames = 2,
    this.minBimanualZoomSpanMeters = 0.08,
    this.maxBimanualZoomSpanMeters = 0.52,
    this.lookaheadSeconds = 0.018,
  }) : _zoomOneEuro = VrOneEuroFilter(
         minCutoffHz: 0.90,
         beta: 5.2,
         derivativeCutoffHz: 1.2,
       ),
       _dialOneEuro = VrOneEuroFilter(
         minCutoffHz: 1.10,
         beta: 4.0,
         derivativeCutoffHz: 1.2,
       );

  final double minConfidenceThreshold;
  final double zoomSmoothingAlpha;
  final int activationConfirmFrames;
  final double minBimanualZoomSpanMeters;
  final double maxBimanualZoomSpanMeters;

  /// Kinematic velocity lookahead (`seconds`) compensating camera + display latency.
  final double lookaheadSeconds;

  final VrOneEuroFilter _zoomOneEuro;
  final VrOneEuroFilter _dialOneEuro;
  final List<VrCustomEMudraBinding> _customBindings = <VrCustomEMudraBinding>[];
  double _smoothedNormalizedZoom = 0.0;
  double _smoothedDialValue = 0.0;
  double _smoothedHandDepthMeters = 0.48;
  int? _lastFusionTimestampUs;
  VrCanonicalEMudra _pendingCandidate = VrCanonicalEMudra.none;
  int _pendingStreak = 0;
  VrCanonicalEMudra _confirmedMudra = VrCanonicalEMudra.none;
  String? _confirmedCustomId;

  List<VrCustomEMudraBinding> get customBindings =>
      List<VrCustomEMudraBinding>.unmodifiable(_customBindings);

  void registerCustomMudra(VrCustomEMudraBinding binding) {
    _customBindings.removeWhere((b) => b.id == binding.id);
    _customBindings.add(binding);
  }

  void unregisterCustomMudra(String id) {
    _customBindings.removeWhere((b) => b.id == id);
  }

  /// Syncs the internal zoom state when the user adjusts zoom manually via UI.
  void setNormalizedZoomBaseline(double normalized01) {
    final clamped = normalized01.clamp(0.0, 1.0);
    _smoothedNormalizedZoom = clamped;
    _zoomOneEuro.reset(clamped);
  }

  void reset() {
    _smoothedNormalizedZoom = 0.0;
    _smoothedDialValue = 0.0;
    _lastFusionTimestampUs = null;
    _zoomOneEuro.reset();
    _dialOneEuro.reset();
    _pendingCandidate = VrCanonicalEMudra.none;
    _pendingStreak = 0;
    _confirmedMudra = VrCanonicalEMudra.none;
    _confirmedCustomId = null;
  }

  /// Evaluates a single camera observation into a candidate mudra.
  ({VrCanonicalEMudra mudra, String? customId}) classifyObservation(
    VrEMudraCameraObservation obs,
  ) {
    if (obs.candidateOverride != null &&
        obs.candidateOverride != VrCanonicalEMudra.none) {
      return (mudra: obs.candidateOverride!, customId: null);
    }
    final left = obs.leftHand;
    final right = obs.rightHand;

    for (final custom in _customBindings) {
      if (custom.matches(left: left, right: right)) {
        return (mudra: VrCanonicalEMudra.custom, customId: custom.id);
      }
    }

    // 1. Bimanual mudras take highest structural specificity:
    if (left != null && right != null) {
      final bothGyanPinch = left.isGyanLike && right.isGyanLike;
      if (bothGyanPinch && obs.bimanualSpanMeters != null) {
        return (mudra: VrCanonicalEMudra.pranaTelescopeZoom, customId: null);
      }
      final bothCenteredRepose =
          !left.isTelarFist &&
          !right.isTelarFist &&
          (obs.bimanualSpanMeters != null && obs.bimanualSpanMeters! <= 0.14) &&
          (left.palmZone == VrPalmOrientationZone.upwardSky ||
              right.palmZone == VrPalmOrientationZone.upwardSky);
      if (bothCenteredRepose) {
        return (mudra: VrCanonicalEMudra.dhyanaStasis, customId: null);
      }
    }

    // 2. Dominant single-hand mudras:
    final primary = right ?? left;
    if (primary == null) {
      return (mudra: VrCanonicalEMudra.none, customId: null);
    }

    if (primary.isAkashLike) {
      return (mudra: VrCanonicalEMudra.akashInvoke, customId: null);
    }
    if (primary.isAbhayaOpenPalm) {
      return (mudra: VrCanonicalEMudra.abhayaRealSight, customId: null);
    }
    if (primary.isTelarFist) {
      return (mudra: VrCanonicalEMudra.telarWeaveGrab, customId: null);
    }
    if (primary.isGyanLike) {
      if (primary.wristRollRadians.abs() > 0.42) {
        return (mudra: VrCanonicalEMudra.suryaTuningDial, customId: null);
      }
      return (mudra: VrCanonicalEMudra.gyanConfirm, customId: null);
    }
    return (mudra: VrCanonicalEMudra.none, customId: null);
  }

  /// Fuses observations from 1, 2, or all 3 cameras (`Visor + Joystick + PC`)
  /// using complementary viewpoint reliability weighting:
  /// `P_fused(m) = 1 - Π_k (1 - w_k * c_k)`.
  VrEMudraFusionState fuseObservations(
    List<VrEMudraCameraObservation> observations, {
    double minZoomRatio = 0.6,
    double maxZoomRatio = 100.0,
  }) {
    final valid = observations
        .where((o) => o.confidence >= 0.15)
        .toList(growable: false);
    if (valid.isEmpty) {
      _pendingCandidate = VrCanonicalEMudra.none;
      _pendingStreak = 0;
      _confirmedMudra = VrCanonicalEMudra.none;
      _confirmedCustomId = null;
      return VrEMudraFusionState(
        activeMudra: VrCanonicalEMudra.none,
        fusedConfidence: 0.0,
        normalizedZoom01: _smoothedNormalizedZoom,
        targetZoomRatio: VrOpticalZoomCurve.normalizedToZoomRatio(
          _smoothedNormalizedZoom,
          minZoom: minZoomRatio,
          maxZoom: maxZoomRatio,
        ),
        dialValue: _smoothedDialValue,
        dominantHandDepthMeters: _smoothedHandDepthMeters,
        contributingCameras: const <VrEMudraCameraRole>{},
      );
    }

    // Compute adaptive dtSeconds from observation timestamps (default 60 Hz)
    var newestTsUs = 0;
    for (final obs in valid) {
      if (obs.timestampMicros > newestTsUs) newestTsUs = obs.timestampMicros;
    }
    var dtSeconds = 1.0 / 60.0;
    if (newestTsUs > 0 &&
        _lastFusionTimestampUs != null &&
        newestTsUs > _lastFusionTimestampUs!) {
      dtSeconds = ((newestTsUs - _lastFusionTimestampUs!) / 1e6).clamp(
        0.004,
        0.10,
      );
    }
    if (newestTsUs > 0) _lastFusionTimestampUs = newestTsUs;

    // Aggregate per-mudra complementary failure probabilities (1 - w_k * c_k)
    final failureProduct = <String, double>{};
    final votersByKey = <String, Set<VrEMudraCameraRole>>{};
    final mudraByKey = <String, (VrCanonicalEMudra, String?)>{};

    double weightedDepthSum = 0.0;
    double depthWeightTotal = 0.0;
    double? bestBimanualSpan;
    double bestSpanWeight = 0.0;
    double? bestRollRadians;
    String bestSignatureCode = '';

    for (final obs in valid) {
      final classified = classifyObservation(obs);
      if (classified.mudra == VrCanonicalEMudra.none) continue;

      final key = classified.mudra == VrCanonicalEMudra.custom
          ? 'custom:${classified.customId}'
          : classified.mudra.name;
      mudraByKey[key] = (classified.mudra, classified.customId);

      final w = obs.cameraRole.baseReliabilityWeight;
      final pSingle = (w * obs.confidence.clamp(0.0, 1.0)).clamp(0.0, 0.98);
      failureProduct[key] = (failureProduct[key] ?? 1.0) * (1.0 - pSingle);
      (votersByKey[key] ??= <VrEMudraCameraRole>{}).add(obs.cameraRole);

      final dom = obs.rightHand ?? obs.leftHand;
      if (dom != null) {
        weightedDepthSum += dom.depthMeters * pSingle;
        depthWeightTotal += pSingle;
        bestRollRadians ??= dom.wristRollRadians;
        if (bestSignatureCode.isEmpty) {
          bestSignatureCode = [
            if (obs.leftHand != null) obs.leftHand!.code,
            if (obs.rightHand != null) obs.rightHand!.code,
          ].join(' | ');
        }
      }
      if (obs.bimanualSpanMeters != null && pSingle > bestSpanWeight) {
        bestSpanWeight = pSingle;
        bestBimanualSpan = obs.bimanualSpanMeters;
      }
    }

    if (depthWeightTotal > 0) {
      final measuredDepth = weightedDepthSum / depthWeightTotal;
      _smoothedHandDepthMeters =
          _smoothedHandDepthMeters * 0.68 + measuredDepth * 0.32;
    }

    // Pick winner with multi-view complementary occlusion bonus when >=2 cameras agree
    String? bestKey;
    var bestConfidence = 0.0;
    var winnerVoterCount = 0;
    for (final entry in failureProduct.entries) {
      var fused = 1.0 - entry.value;
      final voters = votersByKey[entry.key]!;
      if (voters.length >= 2) {
        var bonus = 0.0;
        for (final role in voters) {
          bonus += role.occlusionComplementaryBonus * 0.35;
        }
        fused = (fused + bonus).clamp(0.0, 0.995);
      }
      if (fused > bestConfidence) {
        bestConfidence = fused;
        bestKey = entry.key;
        winnerVoterCount = voters.length;
      }
    }

    final contributing = valid.map((o) => o.cameraRole).toSet();
    var candidateMudra = VrCanonicalEMudra.none;
    String? candidateCustomId;
    if (bestKey != null && bestConfidence >= minConfidenceThreshold) {
      final pair = mudraByKey[bestKey]!;
      candidateMudra = pair.$1;
      candidateCustomId = pair.$2;
    }

    // Fast-path: immediate 0-frame confirmation when >=2 cameras agree with high confidence
    final multiViewFastPath = winnerVoterCount >= 2 && bestConfidence >= 0.82;
    if (candidateMudra == _pendingCandidate) {
      _pendingStreak++;
    } else {
      _pendingCandidate = candidateMudra;
      _pendingStreak = 1;
    }
    if (multiViewFastPath ||
        _pendingStreak >= activationConfirmFrames ||
        candidateMudra == VrCanonicalEMudra.none) {
      _confirmedMudra = candidateMudra;
      _confirmedCustomId = candidateCustomId;
    }

    // Update continuous Prana Telescope Zoom (0.6x <-> 100x) via 1-Euro Filter + Lookahead
    if (_confirmedMudra == VrCanonicalEMudra.pranaTelescopeZoom &&
        bestBimanualSpan != null) {
      final rawNorm =
          ((bestBimanualSpan - minBimanualZoomSpanMeters) /
                  math.max(
                    0.05,
                    maxBimanualZoomSpanMeters - minBimanualZoomSpanMeters,
                  ))
              .clamp(0.0, 1.0);
      if (zoomSmoothingAlpha >= 0.999) {
        _smoothedNormalizedZoom = rawNorm;
        _zoomOneEuro.reset(rawNorm);
      } else {
        _smoothedNormalizedZoom = _zoomOneEuro
            .filter(
              rawNorm,
              dtSeconds: dtSeconds,
              lookaheadSeconds: lookaheadSeconds,
            )
            .clamp(0.0, 1.0);
      }
    }

    // Update continuous Surya Tuning Dial (-1.0 .. +1.0) via 1-Euro Filter
    if (_confirmedMudra == VrCanonicalEMudra.suryaTuningDial &&
        bestRollRadians != null) {
      final rawDial = (bestRollRadians / (math.pi * 0.5)).clamp(-1.0, 1.0);
      _smoothedDialValue = _dialOneEuro
          .filter(
            rawDial,
            dtSeconds: dtSeconds,
            lookaheadSeconds: lookaheadSeconds * 0.5,
          )
          .clamp(-1.0, 1.0);
    }

    final targetZoom = VrOpticalZoomCurve.normalizedToZoomRatio(
      _smoothedNormalizedZoom,
      minZoom: minZoomRatio,
      maxZoom: maxZoomRatio,
    );

    return VrEMudraFusionState(
      activeMudra: _confirmedMudra,
      customMudraId: _confirmedCustomId,
      fusedConfidence: _confirmedMudra == VrCanonicalEMudra.none
          ? 0.0
          : bestConfidence,
      normalizedZoom01: _smoothedNormalizedZoom,
      targetZoomRatio: targetZoom,
      dialValue: _smoothedDialValue,
      dominantHandDepthMeters: _smoothedHandDepthMeters,
      contributingCameras: contributing,
      activeSignatureCode: bestSignatureCode,
    );
  }
}

/// Casiez Adaptive 1-Euro Low-Pass Filter with optional linear kinematic lookahead.
///
/// Eliminates high-frequency hand tremor when holding `50x–100x` Space Zoom steady
/// (`|dx/dt| ≈ 0` -> `minCutoffHz`) while dynamically opening bandwidth (`+beta * |dx/dt|`)
/// during fast bimanual sweeps for near-zero motion-to-photon lag.
class VrOneEuroFilter {
  VrOneEuroFilter({
    this.minCutoffHz = 0.90,
    this.beta = 5.2,
    this.derivativeCutoffHz = 1.2,
  });

  final double minCutoffHz;
  final double beta;
  final double derivativeCutoffHz;

  double? _prevFiltered;
  double _prevDerivative = 0.0;

  void reset([double? initialValue]) {
    _prevFiltered = initialValue;
    _prevDerivative = 0.0;
  }

  static double _smoothingAlpha(double dtSeconds, double cutoffHz) {
    final tau = 1.0 / (2.0 * math.pi * math.max(0.01, cutoffHz));
    return 1.0 / (1.0 + tau / math.max(1e-4, dtSeconds));
  }

  double filter(
    double measurement, {
    double dtSeconds = 1.0 / 60.0,
    double lookaheadSeconds = 0.0,
  }) {
    if (!measurement.isFinite) return _prevFiltered ?? 0.0;
    final prev = _prevFiltered;
    if (prev == null) {
      _prevFiltered = measurement;
      _prevDerivative = 0.0;
      return measurement;
    }
    final dt = dtSeconds.clamp(0.001, 0.25);
    final rawDerivative = (measurement - prev) / dt;
    final alphaD = _smoothingAlpha(dt, derivativeCutoffHz);
    final filteredDerivative =
        _prevDerivative + alphaD * (rawDerivative - _prevDerivative);
    _prevDerivative = filteredDerivative;

    final adaptiveCutoff = minCutoffHz + beta * filteredDerivative.abs();
    final alpha = _smoothingAlpha(dt, adaptiveCutoff);
    final filtered = prev + alpha * (measurement - prev);
    _prevFiltered = filtered;

    if (lookaheadSeconds <= 0) return filtered;
    return filtered + filteredDerivative * lookaheadSeconds;
  }
}

/// Normalized Region-of-Interest (`[0..1] × [0..1]`) eliminating wasted CV pixel
/// processing outside the ergonomic hand interaction frustum.
class VrHandRoiBounds {
  const VrHandRoiBounds({
    required this.uMin,
    required this.uMax,
    required this.vMin,
    required this.vMax,
  });

  /// Lower-central ergonomic ROI for a `0.5x–0.6x` Ultra-Wide visor camera:
  /// skips the upper `30%` ceiling/sky and outer `18%` walls (`42.2%` active area ->
  /// **57.8% pixel reduction** before downsampling).
  static const VrHandRoiBounds visorFrontalHeadsetRoi = VrHandRoiBounds(
    uMin: 0.18,
    uMax: 0.82,
    vMin: 0.30,
    vMax: 0.96,
  );

  /// Dynamic torso-anchored ROI for PC Estación Faro (`~25%` of `1280×720` frame ->
  /// **75% pixel reduction** once torso/head center is localized).
  factory VrHandRoiBounds.desktopTorsoAnchored({
    double centerU = 0.50,
    double centerV = 0.56,
    double widthFraction = 0.42,
    double heightFraction = 0.60,
  }) {
    final halfW = (widthFraction * 0.5).clamp(0.15, 0.50);
    final halfH = (heightFraction * 0.5).clamp(0.15, 0.50);
    final u0 = (centerU - halfW).clamp(0.0, 1.0 - 2 * halfW);
    final v0 = (centerV - halfH).clamp(0.0, 1.0 - 2 * halfH);
    return VrHandRoiBounds(
      uMin: u0,
      uMax: (u0 + 2 * halfW).clamp(0.0, 1.0),
      vMin: v0,
      vMax: (v0 + 2 * halfH).clamp(0.0, 1.0),
    );
  }

  final double uMin;
  final double uMax;
  final double vMin;
  final double vMax;

  double get areaFraction =>
      ((uMax - uMin).clamp(0.0, 1.0)) * ((vMax - vMin).clamp(0.0, 1.0));

  double get savedPixelFraction => (1.0 - areaFraction).clamp(0.0, 1.0);

  bool containsUv(double u, double v) =>
      u >= uMin && u <= uMax && v >= vMin && v <= vMax;
}

/// Zero-waste hierarchical Tri-Camera duty-cycle schedule ("Lazy Wakeup" +
/// Zoom-Aware Telephoto Shedding).
class VrTriCameraSensingSchedule {
  const VrTriCameraSensingSchedule({
    required this.runDesktopVision,
    required this.runJoystickPalmarAssist,
    required this.runVisorCvStream,
    required this.visorAnalysisIntervalMs,
    required this.reason,
  });

  final bool runDesktopVision;
  final bool runJoystickPalmarAssist;
  final bool runVisorCvStream;

  /// `0` when Visor CV stream is hibernated; `66` (`~15 Hz`, `5x` faster than legacy `300 ms`) when active.
  final int visorAnalysisIntervalMs;
  final String reason;

  /// Maximum zoom ratio where hands remain inside the Visor's camera cone.
  /// Above `1.8x` (e.g. `3x`, `10x`, `30x`, `100x` Space Zoom), hands cannot
  /// physically focus or fit in the narrow telephoto FoV (`24° -> 0.25°`), so
  /// Visor CV analysis is immediately shed to `0 Hz`.
  static const double maxHandSensingZoomRatio = 1.80;

  /// Head yaw angle (`75°` in radians) beyond which the user has turned away
  /// from the Desktop Faro webcam and wakes local Visor/Joystick CV.
  static const double desktopTurnAwayYawRadians = 75.0 * math.pi / 180.0;

  factory VrTriCameraSensingSchedule.compute({
    required bool beaconConnected,
    required double desktopHandConfidence,
    required double headYawFromDesktopRadians,
    required double visorZoomRatio,
    required bool visorCameraActive,
    bool hasLocalAnalysisConsumer = true,
  }) {
    final telephotoZoomActive = visorZoomRatio > maxHandSensingZoomRatio;
    final turnedAwayFromDesktop =
        headYawFromDesktopRadians.abs() > desktopTurnAwayYawRadians;

    if (beaconConnected) {
      // State 1: Desktop sees hands clearly & user faces desk -> hibernate BOTH mobile CV streams!
      if (!turnedAwayFromDesktop && desktopHandConfidence >= 0.80) {
        return const VrTriCameraSensingSchedule(
          runDesktopVision: true,
          runJoystickPalmarAssist: false,
          runVisorCvStream: false,
          visorAnalysisIntervalMs: 0,
          reason: 'pc_primary_mobile_cv_hibernated',
        );
      }

      // State 2: Self-occlusion / fine palmar mudra -> wake ONLY upward Joystick palmar ROI!
      if (!turnedAwayFromDesktop && desktopHandConfidence >= 0.35) {
        return const VrTriCameraSensingSchedule(
          runDesktopVision: true,
          runJoystickPalmarAssist: true,
          runVisorCvStream: false,
          visorAnalysisIntervalMs: 0,
          reason: 'pc_plus_joystick_palmar_assist',
        );
      }

      // State 3: Turned away from PC or hands occluded from desk -> wake Visor ROI unless in telephoto zoom
      final canUseVisor =
          visorCameraActive && hasLocalAnalysisConsumer && !telephotoZoomActive;
      return VrTriCameraSensingSchedule(
        runDesktopVision: true,
        runJoystickPalmarAssist: true,
        runVisorCvStream: canUseVisor,
        visorAnalysisIntervalMs: canUseVisor ? 66 : 0,
        reason: telephotoZoomActive
            ? 'telephoto_zoom_shed_visor_cv'
            : 'turned_away_or_occluded_local_wakeup',
      );
    }

    // Standalone 1D / 2D-VR mode (no PC connected):
    if (telephotoZoomActive) {
      return const VrTriCameraSensingSchedule(
        runDesktopVision: false,
        runJoystickPalmarAssist: true,
        runVisorCvStream: false,
        visorAnalysisIntervalMs: 0,
        reason: 'standalone_telephoto_shed_visor_cv',
      );
    }

    final useVisor = visorCameraActive && hasLocalAnalysisConsumer;
    return VrTriCameraSensingSchedule(
      runDesktopVision: false,
      runJoystickPalmarAssist: true,
      runVisorCvStream: useVisor,
      visorAnalysisIntervalMs: useVisor ? 66 : 0,
      reason: 'standalone_low_latency_roi',
    );
  }
}
