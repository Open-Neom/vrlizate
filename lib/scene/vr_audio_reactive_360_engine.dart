import 'dart:math';

import 'package:flutter/material.dart';

import '../components/vr_element.dart';
import '../components/vr_scene.dart';
import '../core/camera/vr_camera.dart';
import '../core/projection/stereoscopic_projection.dart';
import '../utils/vr_math.dart';

/// Audio-reactive 360° VR universe built on `vrlizate`'s [VRScene], [VRCamera],
/// and [StereoscopicProjection].
///
/// Manages star particles, concentric pulsing rings, and star constellations
/// driven by real-time audio amplitude, frequency, beat, phase, and coherence.
class VrAudioReactive360Engine extends ChangeNotifier {
  final Random _random = Random();

  /// Underlying VR scene storing visual elements.
  final VRScene scene = VRScene();

  /// 3D viewpoint VR camera.
  final VRCamera camera = VRCamera();

  /// Stereoscopic side-by-side projection for VR headsets.
  final StereoscopicProjection projection = StereoscopicProjection();

  /// Floating star particles reactive to audio.
  List<AudioParticle> particles = [];

  /// Concentric ring particles reactive to audio.
  List<AudioParticle> rings = [];

  /// Constellation star particles linked by connection lines.
  List<AudioParticle> constellations = [];

  /// Current audio signal amplitude in `[0.0, 1.0]`.
  double audioAmplitude = 0.0;

  /// Dominant audio frequency in Hertz (e.g. `432.0` Hz).
  double audioFrequency = 432.0;

  /// Audio pulse / tempo driving beat animations.
  double audioBeat = 0.0;

  /// Current audio wave phase for continuous animations.
  double audioPhase = 0.0;

  /// Hemispheric audio coherence in `[0.0, 1.0]`.
  double audioCoherence = 0.5;

  /// Orbital radius multiplier.
  double wavelength = 1.0;

  double _time = 0.0;

  /// Maximum floating star particle count.
  int particleCount = 200;

  /// Concentric ring count generated on initialization.
  int ringCount = 8;

  /// Whether concentric reactive rings are visible.
  bool showRings = true;

  /// Whether star constellations and connections are visible.
  bool showConstellations = true;

  /// Whether cosmic nebula glow is enabled.
  bool showNebula = true;

  /// Active palette primary color.
  Color primaryColor = const Color(0xFF00CED1);

  /// Active palette secondary color.
  Color secondaryColor = const Color(0xFF6A5ACD);

  /// Active palette accent color.
  Color accentColor = const Color(0xFFFF6B6B);

  /// Eye separation (delegates to [projection]).
  double get eyeSeparation => projection.eyeSeparation;
  set eyeSeparation(double v) => projection.eyeSeparation = v;

  /// Initializes the procedural 360° VR universe.
  void initialize() {
    particles.clear();
    rings.clear();
    constellations.clear();
    scene.clear();

    for (int i = 0; i < particleCount; i++) {
      final theta = _random.nextDouble() * 2 * pi;
      final phi = (_random.nextDouble() * 2 - 1) * pi / 2;
      final radius = 0.8 + _random.nextDouble() * 0.4;

      final p = AudioParticle(
        vrElement: VRParticle(
          position: Offset3D.fromSpherical(theta, phi, radius),
          radius: 1.0 + _random.nextDouble() * 3.0,
          color: _getRandomStarColor(),
          glowRadius: 4,
        ),
        energy: 0.3 + _random.nextDouble() * 0.7,
        pulsePhase: _random.nextDouble() * 2 * pi,
        theta: theta,
        phi: phi,
        baseRadius: radius,
      );
      particles.add(p);
      scene.addElement(p.vrElement);
    }

    for (int i = 0; i < ringCount; i++) {
      final ringRadius = 0.3 + (i / ringCount) * 0.6;
      final pointsInRing = 60 + i * 10;
      for (int j = 0; j < pointsInRing; j++) {
        final theta = (j / pointsInRing) * 2 * pi;
        final p = AudioParticle(
          vrElement: VRParticle(
            position: Offset3D.fromSpherical(theta, 0, ringRadius),
            radius: 1.5,
            color: primaryColor,
            glowRadius: 2,
          ),
          energy: 1.0,
          pulsePhase: i * 0.5,
          theta: theta,
          phi: 0,
          baseRadius: ringRadius,
        );
        rings.add(p);
        scene.addElement(p.vrElement);
      }
    }

    _generateConstellations();
  }

  void _generateConstellations() {
    final numConstellations = 5 + _random.nextInt(4);
    for (int c = 0; c < numConstellations; c++) {
      final centerTheta = _random.nextDouble() * 2 * pi;
      final centerPhi = (_random.nextDouble() * 2 - 1) * pi / 3;
      final starCount = 3 + _random.nextInt(5);
      final groupParticles = <AudioParticle>[];

      for (int s = 0; s < starCount; s++) {
        final theta = centerTheta + (_random.nextDouble() - 0.5) * 0.3;
        final phi = centerPhi + (_random.nextDouble() - 0.5) * 0.2;
        final p = AudioParticle(
          vrElement: VRParticle(
            position: Offset3D.fromSpherical(theta, phi, 0.95),
            radius: 2.0 + _random.nextDouble() * 2.0,
            color: Colors.white,
            glowRadius: 5,
          ),
          energy: 0.8,
          pulsePhase: c.toDouble(),
          theta: theta,
          phi: phi,
          baseRadius: 0.95,
        );
        constellations.add(p);
        groupParticles.add(p);
        scene.addElement(p.vrElement);
      }

      for (int i = 0; i < groupParticles.length - 1; i++) {
        scene.addConnection(
          VRConnection(
            a: groupParticles[i].vrElement,
            b: groupParticles[i + 1].vrElement,
            color: accentColor.withValues(alpha: 0.4),
            strokeWidth: 1.2,
          ),
        );
      }
    }
  }

  Color _getRandomStarColor() {
    final colors = [
      Colors.white,
      const Color(0xFFFFE4B5),
      const Color(0xFFADD8E6),
      const Color(0xFFFFB6C1),
      primaryColor.withValues(alpha: 0.8),
    ];
    return colors[_random.nextInt(colors.length)];
  }

  /// Log-normalized frequency in `[0.0, 1.0]` across `40..1500` Hz.
  double get normalizedFrequency {
    const minF = 40.0, maxF = 1500.0;
    return ((log(audioFrequency.clamp(minF, maxF)) - log(minF)) /
            (log(maxF) - log(minF)))
        .clamp(0.0, 1.0);
  }

  /// HSL-modulated accent color derived from [normalizedFrequency] and [audioAmplitude].
  Color get frequencyModulatedColor {
    final hue = 240 - (normalizedFrequency * 180);
    return HSLColor.fromAHSL(
      1.0,
      hue,
      0.8,
      0.5 + audioAmplitude * 0.2,
    ).toColor();
  }

  /// Updates audio state parameters to modulate reactive graphics.
  void updateAudio({
    required double amplitude,
    required double frequency,
    required double beat,
    required double phase,
    required double coherence,
    double? waveLen,
  }) {
    audioAmplitude = amplitude.clamp(0.0, 1.0);
    audioFrequency = frequency;
    audioBeat = beat.clamp(0.0, 40.0);
    audioPhase = phase;
    audioCoherence = coherence.clamp(0.0, 1.0);
    if (waveLen != null) wavelength = waveLen.clamp(0.5, 2.0);
  }

  /// Advances all procedural elements by [dt] seconds.
  void update(double dt) {
    _time += dt;
    camera.update(dt);

    for (final p in particles) {
      final freqFactor = 1.0 + normalizedFrequency * 0.5;
      p.energy =
          0.3 +
          0.7 *
              ((sin(_time * 2 * freqFactor + p.pulsePhase) + 1) / 2) *
              audioAmplitude;
      final newRadius = p.baseRadius * wavelength;
      final oldElement = p.vrElement as VRParticle;
      final newColor = Color.lerp(
        _getRandomStarColor(),
        frequencyModulatedColor,
        normalizedFrequency * 0.3,
      )!.withValues(alpha: 0.5 + 0.5 * p.energy);
      final newElement = VRParticle(
        position: Offset3D.fromSpherical(p.theta, p.phi, newRadius),
        radius: oldElement.radius,
        color: newColor,
        glowRadius: oldElement.glowRadius,
        visible: oldElement.visible,
      );
      final idx = scene.elements.indexOf(oldElement);
      if (idx != -1) {
        scene.elements[idx] = newElement;
      }
      p.vrElement = newElement;
    }

    for (final r in rings) {
      final freqSpeed = 0.5 + normalizedFrequency * 1.5;
      final pulse =
          sin(_time * audioBeat * freqSpeed + r.pulsePhase) *
          audioAmplitude *
          0.1;
      final newRadius = (r.baseRadius + pulse) * wavelength;
      final oldElement = r.vrElement as VRParticle;
      final newColor = Color.lerp(
        secondaryColor,
        frequencyModulatedColor,
        normalizedFrequency * 0.5,
      )!.withValues(alpha: 0.6 + audioAmplitude * 0.4);
      final newElement = VRParticle(
        position: Offset3D.fromSpherical(r.theta, r.phi, newRadius),
        radius: oldElement.radius,
        color: newColor,
        glowRadius: oldElement.glowRadius,
        visible: oldElement.visible,
      );
      final idx = scene.elements.indexOf(oldElement);
      if (idx != -1) {
        scene.elements[idx] = newElement;
      }
      r.vrElement = newElement;
    }

    for (final c in constellations) {
      c.energy = 0.5 + 0.5 * sin(_time * 1.5 + c.pulsePhase) * audioCoherence;
      final oldElement = c.vrElement as VRParticle;
      final newColor = Colors.white.withValues(alpha: 0.5 + 0.5 * c.energy);
      final newElement = VRParticle(
        position: oldElement.position,
        radius: oldElement.radius,
        color: newColor,
        glowRadius: oldElement.glowRadius,
        visible: oldElement.visible,
      );
      final idx = scene.elements.indexOf(oldElement);
      if (idx != -1) {
        scene.elements[idx] = newElement;
      }
      c.vrElement = newElement;
    }

    notifyListeners();
  }

  /// Rotates [camera] by [deltaTheta] and [deltaPhi] radians.
  void updateCamera(double deltaTheta, double deltaPhi) {
    camera.rotate(deltaTheta, deltaPhi);
  }

  /// Applies a named chromatic palette (`calm`, `focus`, `sleep`, `creativity`).
  void setColorTheme(String mode) {
    switch (mode) {
      case 'calm':
        primaryColor = const Color(0xFF4B0082);
        secondaryColor = const Color(0xFF9370DB);
        accentColor = const Color(0xFFE6E6FA);
      case 'focus':
        primaryColor = const Color(0xFFFFA500);
        secondaryColor = const Color(0xFFFF6347);
        accentColor = const Color(0xFFFFD700);
      case 'sleep':
        primaryColor = const Color(0xFF191970);
        secondaryColor = const Color(0xFF000080);
        accentColor = const Color(0xFF4169E1);
      case 'creativity':
        primaryColor = const Color(0xFFFF1493);
        secondaryColor = const Color(0xFF00CED1);
        accentColor = const Color(0xFF7B68EE);
      default:
        primaryColor = const Color(0xFF00CED1);
        secondaryColor = const Color(0xFF6A5ACD);
        accentColor = const Color(0xFFFF6B6B);
    }
  }
}

/// Animated audio-reactive particle element inside [VrAudioReactive360Engine].
class AudioParticle {
  /// Visual element rendered in the 3D `vrlizate` scene.
  VRElement vrElement;

  /// Pulsation energy level.
  double energy;

  /// Phase offset in radians.
  double pulsePhase;

  /// Horizontal spherical angle (theta) in radians.
  double theta;

  /// Vertical spherical angle (phi) in radians.
  double phi;

  /// Base orbital radius from the 3D scene origin.
  double baseRadius;

  AudioParticle({
    required this.vrElement,
    required this.energy,
    required this.pulsePhase,
    required this.theta,
    required this.phi,
    required this.baseRadius,
  });
}
