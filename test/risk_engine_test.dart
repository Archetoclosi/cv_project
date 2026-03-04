import 'package:flutter_test/flutter_test.dart';
import 'package:ping/services/risk_engine/feature_vector.dart';
import 'package:ping/services/risk_engine/risk_engine.dart';
import 'package:ping/services/risk_engine/risk_score.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Baseline safe scenario: device in hand, no phone visible, normal tilt.
FeatureVector _safe() => FeatureVector(
      phoneDetected: false,
      phoneConfidence: 0.0,
      phonePersistence: 0.0,
      phoneAreaRatio: 0.0,
      phoneCenterX: 0.5,
      phoneCenterY: 0.5,
      faceDetected: false,
      faceCount: 0,
      accelMagnitudeMean: 9.8,
      accelMagnitudeStd: 0.8, // moving
      gyroMagnitudeMean: 0.1,
      gyroMagnitudeStd: 0.12,
      tiltAngle: 90.0, // vertical, normal use
      magMagnitudeStd: 0.1,
    );

/// High-risk scenario: phone detected, stationary, tilt in photo range, face visible.
FeatureVector _critical() => FeatureVector(
      phoneDetected: true,
      phoneConfidence: 0.91,
      phonePersistence: 0.88,
      phoneAreaRatio: 0.12,
      phoneCenterX: 0.51, // centered
      phoneCenterY: 0.48,
      faceDetected: true,
      faceCount: 1,
      accelMagnitudeMean: 9.81,
      accelMagnitudeStd: 0.05, // stationary
      gyroMagnitudeMean: 0.01,
      gyroMagnitudeStd: 0.02,
      tiltAngle: 53.0, // peak photo angle
      magMagnitudeStd: 0.2,
    );

/// Phone detected but device is moving (shaking hands, walking).
FeatureVector _phoneButMoving() => FeatureVector(
      phoneDetected: true,
      phoneConfidence: 0.75,
      phonePersistence: 0.60,
      phoneAreaRatio: 0.08,
      phoneCenterX: 0.55,
      phoneCenterY: 0.50,
      faceDetected: false,
      faceCount: 0,
      accelMagnitudeMean: 10.5,
      accelMagnitudeStd: 1.20, // moving significantly
      gyroMagnitudeMean: 0.5,
      gyroMagnitudeStd: 0.40,
      tiltAngle: 88.0, // not in photo range
      magMagnitudeStd: 0.15,
    );

/// Phone detected, stationary, but tilt is wrong (screen flat on table).
FeatureVector _phoneStationaryWrongTilt() => FeatureVector(
      phoneDetected: true,
      phoneConfidence: 0.80,
      phonePersistence: 0.70,
      phoneAreaRatio: 0.09,
      phoneCenterX: 0.52,
      phoneCenterY: 0.50,
      faceDetected: false,
      faceCount: 0,
      accelMagnitudeMean: 9.80,
      accelMagnitudeStd: 0.04, // stationary
      gyroMagnitudeMean: 0.01,
      gyroMagnitudeStd: 0.01,
      tiltAngle: 5.0, // flat on table — not a threat
      magMagnitudeStd: 0.10,
    );

/// Phone detected with very low confidence / persistence (fleeting detection).
FeatureVector _weakPhoneSignal() => FeatureVector(
      phoneDetected: true,
      phoneConfidence: 0.40,
      phonePersistence: 0.20, // phoneStrength = 0.08 < threshold
      phoneAreaRatio: 0.03,
      phoneCenterX: 0.80, // off to the side
      phoneCenterY: 0.20,
      faceDetected: false,
      faceCount: 0,
      accelMagnitudeMean: 9.82,
      accelMagnitudeStd: 0.06,
      gyroMagnitudeMean: 0.02,
      gyroMagnitudeStd: 0.02,
      tiltAngle: 55.0,
      magMagnitudeStd: 0.12,
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('RiskEngine — RiskLevel classification', () {
    test('safe scenario produces SAFE level', () {
      final engine = RiskEngine();
      // Feed multiple identical frames to stabilise the smoother
      late RiskScore result;
      for (int i = 0; i < 5; i++) {
        result = engine.evaluate(_safe());
      }

      expect(result.level, equals(RiskLevel.safe));
      expect(result.smoothedValue, lessThan(0.25));
      expect(result.contributingFactors, isEmpty);
    });

    test('critical scenario produces CRITICAL level', () {
      final engine = RiskEngine();
      late RiskScore result;
      for (int i = 0; i < 5; i++) {
        result = engine.evaluate(_critical());
      }

      expect(result.level, equals(RiskLevel.critical));
      expect(result.smoothedValue, greaterThan(0.80));
    });

    test('critical scenario triggers triple correlation factor', () {
      final engine = RiskEngine();
      final result = engine.evaluate(_critical());

      expect(
        result.contributingFactors.any((f) => f.startsWith('TRIPLE_CORRELATION')),
        isTrue,
      );
    });

    test('phone but moving → at most CAUTION', () {
      final engine = RiskEngine();
      late RiskScore result;
      for (int i = 0; i < 5; i++) {
        result = engine.evaluate(_phoneButMoving());
      }

      expect(result.level, isNot(equals(RiskLevel.critical)));
      expect(result.level, isNot(equals(RiskLevel.elevated)));
    });

    test('phone stationary with wrong tilt → no triple correlation', () {
      final engine = RiskEngine();
      final result = engine.evaluate(_phoneStationaryWrongTilt());

      expect(
        result.contributingFactors.any((f) => f.startsWith('TRIPLE_CORRELATION')),
        isFalse,
      );
    });
  });

  group('RiskEngine — weak signal filtering', () {
    test('weak phone signal below threshold is ignored', () {
      final engine = RiskEngine();
      final result = engine.evaluate(_weakPhoneSignal());

      // phoneStrength = 0.40 * 0.20 = 0.08 < default threshold 0.15
      expect(
        result.contributingFactors.any((f) => f.startsWith('phone_detected')),
        isFalse,
      );
      expect(result.level, equals(RiskLevel.safe));
    });
  });

  group('RiskEngine — temporal smoother behaviour', () {
    test('score rises fast on sudden threat', () {
      final engine = RiskEngine();
      // Warm up with safe frames
      for (int i = 0; i < 3; i++) {
        engine.evaluate(_safe());
      }
      // Inject critical frame
      final result = engine.evaluate(_critical());

      // Even a single critical frame should push smoothed above safe
      expect(result.smoothedValue, greaterThan(0.25));
    });

    test('score decays slowly after threat disappears', () {
      final engine = RiskEngine();
      // Build up threat
      for (int i = 0; i < 5; i++) {
        engine.evaluate(_critical());
      }
      final peakScore = engine.currentScore;

      // Now feed safe frames
      engine.evaluate(_safe());
      final afterOneSafe = engine.currentScore;

      // One safe frame should NOT drop the score all the way down
      expect(afterOneSafe, greaterThan(peakScore * 0.5));
    });

    test('reset() clears smoother state', () {
      final engine = RiskEngine();
      for (int i = 0; i < 5; i++) {
        engine.evaluate(_critical());
      }
      engine.reset();

      expect(engine.currentScore, equals(0.0));
      expect(engine.recentPeak, equals(0.0));
    });
  });

  group('RiskEngine — config variants', () {
    test('conservative config produces lower scores than default', () {
      final defaultEngine = RiskEngine();
      final conservativeEngine = RiskEngine(config: RiskEngineConfig.conservative());

      final defaultResult = defaultEngine.evaluate(_critical());
      final conservativeResult = conservativeEngine.evaluate(_critical());

      expect(conservativeResult.value, lessThanOrEqualTo(defaultResult.value));
    });

    test('aggressive config produces higher scores than default', () {
      final defaultEngine = RiskEngine();
      final aggressiveEngine = RiskEngine(config: RiskEngineConfig.aggressive());

      final defaultResult = defaultEngine.evaluate(_phoneButMoving());
      final aggressiveResult = aggressiveEngine.evaluate(_phoneButMoving());

      expect(aggressiveResult.value, greaterThanOrEqualTo(defaultResult.value));
    });
  });

  group('RiskScore — level thresholds', () {
    test('0.00 → safe', () => expect(RiskScore.levelFromScore(0.00), RiskLevel.safe));
    test('0.24 → safe', () => expect(RiskScore.levelFromScore(0.24), RiskLevel.safe));
    test('0.25 → caution', () => expect(RiskScore.levelFromScore(0.25), RiskLevel.caution));
    test('0.54 → caution', () => expect(RiskScore.levelFromScore(0.54), RiskLevel.caution));
    test('0.55 → elevated', () => expect(RiskScore.levelFromScore(0.55), RiskLevel.elevated));
    test('0.79 → elevated', () => expect(RiskScore.levelFromScore(0.79), RiskLevel.elevated));
    test('0.80 → critical', () => expect(RiskScore.levelFromScore(0.80), RiskLevel.critical));
    test('1.00 → critical', () => expect(RiskScore.levelFromScore(1.00), RiskLevel.critical));
  });
}

