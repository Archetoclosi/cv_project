import 'risk_score.dart';
import 'feature_vector.dart';
import '../temporal_smoother.dart';

/// Configuration for the Risk Engine weights and thresholds.
/// All [weight_*] fields represent the maximum contribution of that signal
/// to the final score. Their sum should not exceed 1.0.
///
/// Tune these values with real-world data once you have a labeled dataset.
class RiskEngineConfig {
  // ─── Vision weights ───────────────────────────────────────────────────────

  /// Base contribution when a phone is detected with persistence > 0.
  /// This is the single strongest signal.
  final double weightPhoneBase;

  /// Bonus when the phone has high area ratio (close / prominent).
  final double weightPhoneProximity;

  /// Bonus when phone is centered in frame (likely deliberately aimed).
  final double weightPhoneCentered;

  /// Contribution from a face being visible (implies a person present).
  final double weightFacePresent;

  // ─── IMU weights ──────────────────────────────────────────────────────────

  /// Bonus when the device is stationary while a phone is visible.
  /// Stationarity alone = 0 contribution (you're just holding your phone).
  final double weightStationaryWithPhone;

  /// Bonus when tilt is in the typical photography range [30°–75°].
  final double weightTiltInPhotoRange;

  // ─── Composite signal weights ─────────────────────────────────────────────

  /// Extra bonus for the triple: phone + stationary + tilt in range.
  /// This is the highest-confidence single signal.
  final double weightTripleCorrelation;

  // ─── Thresholds ───────────────────────────────────────────────────────────

  /// Minimum phoneStrength (confidence × persistence) to count the phone
  /// as a real detection. Below this, phone signals are ignored.
  final double phoneStrengthThreshold;

  /// Below this accelMagnitudeStd, device is considered stationary.
  final double stationaryAccelThreshold;

  /// Below this gyroMagnitudeStd, device is considered stationary.
  final double stationaryGyroThreshold;

  /// Phone bbox center X must be within this distance from 0.5 to count
  /// as "centered". E.g. 0.2 → center band is [0.3, 0.7].
  final double centeredXTolerance;

  /// Minimum bbox area ratio to add the proximity bonus.
  final double phoneProximityAreaThreshold;

  const RiskEngineConfig({
    this.weightPhoneBase = 0.38,
    this.weightPhoneProximity = 0.08,
    this.weightPhoneCentered = 0.06,
    this.weightFacePresent = 0.07,
    this.weightStationaryWithPhone = 0.12,
    this.weightTiltInPhotoRange = 0.08,
    this.weightTripleCorrelation = 0.21,
    this.phoneStrengthThreshold = 0.15,
    this.stationaryAccelThreshold = 0.30,
    this.stationaryGyroThreshold = 0.05,
    this.centeredXTolerance = 0.20,
    this.phoneProximityAreaThreshold = 0.05,
  }) : assert(
         weightPhoneBase +
                 weightPhoneProximity +
                 weightPhoneCentered +
                 weightFacePresent +
                 weightStationaryWithPhone +
                 weightTiltInPhotoRange +
                 weightTripleCorrelation <=
             1.001,
         'Sum of weights must not exceed 1.0',
       );

  /// A conservative config: reduces false positives, increases false negatives.
  /// Useful in environments with lots of phones (offices, public spaces).
  factory RiskEngineConfig.conservative() => const RiskEngineConfig(
    weightPhoneBase: 0.30,
    weightPhoneProximity: 0.06,
    weightPhoneCentered: 0.04,
    weightFacePresent: 0.05,
    weightStationaryWithPhone: 0.10,
    weightTiltInPhotoRange: 0.06,
    weightTripleCorrelation: 0.18,
    phoneStrengthThreshold: 0.25,
  );

  /// An aggressive config: maximizes sensitivity, may increase false positives.
  factory RiskEngineConfig.aggressive() => const RiskEngineConfig(
    weightPhoneBase: 0.40,
    weightPhoneProximity: 0.09,
    weightPhoneCentered: 0.07,
    weightFacePresent: 0.07,
    weightStationaryWithPhone: 0.13,
    weightTiltInPhotoRange: 0.08,
    weightTripleCorrelation: 0.16,
    phoneStrengthThreshold: 0.10,
  );
}

/// ─────────────────────────────────────────────────────────────────────────────
/// The Risk Engine.
///
/// Evaluates a [FeatureVector] and produces a [RiskScore] representing the
/// probability that someone is capturing the on-screen content with
/// an external device.
///
/// Usage:
/// ```dart
/// final engine = RiskEngine();
///
/// // Call this every time you have a new FeatureVector (e.g. every 500ms–2s)
/// final score = engine.evaluate(featureVector);
///
/// // Use score.smoothedValue and score.level to drive your UI
/// ```
/// ─────────────────────────────────────────────────────────────────────────────
class RiskEngine {
  final RiskEngineConfig config;
  final TemporalSmoother _smoother;

  RiskEngine({RiskEngineConfig? config, TemporalSmoother? smoother})
    : config = config ?? const RiskEngineConfig(),
      _smoother = smoother ?? TemporalSmoother();

  /// Evaluate a single [FeatureVector] and return a [RiskScore].
  RiskScore evaluate(FeatureVector f) {
    double score = 0.0;
    final factors = <String>[];

    // ── 1. Phone detection (base signal) ──────────────────────────────────
    //
    // We weight by phoneStrength (confidence × persistence) to avoid
    // reacting to a single fleeting frame.
    if (f.phoneDetected && f.phoneStrength >= config.phoneStrengthThreshold) {
      final contribution = config.weightPhoneBase * f.phoneStrength;
      score += contribution;
      factors.add(
        'phone_detected '
        '(strength=${f.phoneStrength.toStringAsFixed(2)}, '
        '+${contribution.toStringAsFixed(3)})',
      );

      // ── 1a. Proximity bonus ─────────────────────────────────────────────
      if (f.phoneAreaRatio >= config.phoneProximityAreaThreshold) {
        final proximityFactor = (f.phoneAreaRatio / 0.30).clamp(0.0, 1.0);
        final contribution2 = config.weightPhoneProximity * proximityFactor;
        score += contribution2;
        factors.add(
          'phone_close '
          '(area=${f.phoneAreaRatio.toStringAsFixed(2)}, '
          '+${contribution2.toStringAsFixed(3)})',
        );
      }

      // ── 1b. Centered bonus ──────────────────────────────────────────────
      final distFromCenter = (f.phoneCenterX - 0.5).abs();
      if (distFromCenter <= config.centeredXTolerance) {
        final centerScore = 1.0 - (distFromCenter / config.centeredXTolerance);
        final contribution3 = config.weightPhoneCentered * centerScore;
        score += contribution3;
        factors.add(
          'phone_centered '
          '(dist=${distFromCenter.toStringAsFixed(2)}, '
          '+${contribution3.toStringAsFixed(3)})',
        );
      }
    }

    // ── 2. Face presence ──────────────────────────────────────────────────
    //
    // A face means someone is actively pointing a device — not just a
    // phone lying on a table.
    if (f.faceDetected) {
      final faceBonus = f.faceCount > 1
          ? config.weightFacePresent *
                1.2 // multiple faces = more suspicious
          : config.weightFacePresent;
      final clampedFaceBonus = faceBonus.clamp(
        0.0,
        config.weightFacePresent * 1.2,
      );
      score += clampedFaceBonus;
      factors.add(
        'face_present '
        '(count=${f.faceCount}, '
        '+${clampedFaceBonus.toStringAsFixed(3)})',
      );
    }

    // ── 3. Stationary + phone ─────────────────────────────────────────────
    //
    // Stationarity alone is meaningless. It only matters when the phone
    // has already been detected.
    if (f.phoneAndStationary) {
      score += config.weightStationaryWithPhone;
      factors.add(
        'stationary_with_phone '
        '(accelStd=${f.accelMagnitudeStd.toStringAsFixed(3)}, '
        '+${config.weightStationaryWithPhone.toStringAsFixed(3)})',
      );
    }

    // ── 4. Tilt in photo range ────────────────────────────────────────────
    //
    // The tilt range [30°–75°] corresponds to a typical angle for pointing
    // a phone at another screen. We scale by how "central" the angle is
    // within this range (peak at ~52°).
    if (f.tiltInPhotoRange) {
      // Bell-curve-like scoring: peak at 52°, falls off towards edges
      final tiltCenter = 52.5;
      final tiltNormalized = 1.0 - ((f.tiltAngle - tiltCenter).abs() / 22.5);
      final tiltScore = tiltNormalized.clamp(0.0, 1.0);
      final contribution = config.weightTiltInPhotoRange * tiltScore;
      score += contribution;
      factors.add(
        'tilt_in_photo_range '
        '(angle=${f.tiltAngle.toStringAsFixed(1)}°, '
        '+${contribution.toStringAsFixed(3)})',
      );
    }

    // ── 5. Triple correlation (highest-confidence signal) ─────────────────
    //
    // Phone detected + device stationary + tilt in photo range.
    // These three together are highly unlikely to be coincidental.
    if (f.phoneAndStationary &&
        f.tiltInPhotoRange &&
        f.phoneStrength >= config.phoneStrengthThreshold) {
      score += config.weightTripleCorrelation;
      factors.add(
        'TRIPLE_CORRELATION '
        '(phone+stationary+tilt, '
        '+${config.weightTripleCorrelation.toStringAsFixed(3)})',
      );
    }

    // ── Clamp final score ─────────────────────────────────────────────────
    final rawScore = score.clamp(0.0, 1.0);

    // ── Temporal smoothing ────────────────────────────────────────────────
    final smoothed = _smoother.update(rawScore);

    return RiskScore(
      value: rawScore,
      smoothedValue: smoothed,
      level: RiskScore.levelFromScore(smoothed),
      contributingFactors: factors,
      timestamp: DateTime.now().toUtc(),
    );
  }

  /// Reset the smoother (call when the protected view is closed/hidden).
  void reset() => _smoother.reset();

  /// Current smoothed score without re-evaluating.
  double get currentScore => _smoother.current;

  /// Recent peak score (useful for "alert in last N seconds" UI).
  double get recentPeak => _smoother.recentPeak;
}
