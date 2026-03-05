import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'risk_engine/feature_vector.dart';
import 'risk_engine/risk_engine.dart';
import 'risk_engine/risk_score.dart';
import 'temporal_smoother.dart';

/// Versione ML del Risk Engine.
///
/// Chiama il modello Core ML via MethodChannel (MLRiskEngineChannel.swift).
/// Se il modello non è disponibile (simulatore, modello non ancora copiato,
/// dispositivo non supportato), fa automaticamente fallback al rule-based engine.
///
/// L'interfaccia è identica a [RiskEngine] — drop-in replacement.
class MLRiskEngine {
  static const _channel = MethodChannel('com.yourapp/ml_risk_engine');

  final RiskEngine _fallback;
  final TemporalSmoother _smoother;

  bool _modelAvailable = true; // ottimistico, si aggiorna al primo errore

  MLRiskEngine({RiskEngineConfig? fallbackConfig, TemporalSmoother? smoother})
    : _fallback = RiskEngine(config: fallbackConfig),
      _smoother = smoother ?? TemporalSmoother();

  /// Verifica se il modello Core ML è disponibile sul dispositivo.
  Future<bool> checkModelAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isModelLoaded');
      _modelAvailable = result ?? false;
      return _modelAvailable;
    } catch (_) {
      _modelAvailable = false;
      return false;
    }
  }

  /// Valuta un [FeatureVector] e restituisce un [RiskScore].
  /// Usa il modello ML se disponibile, altrimenti il rule-based engine.
  Future<RiskScore> evaluate(FeatureVector f) async {
    if (!_modelAvailable) {
      return _evaluateWithFallback(f);
    }

    try {
      final result = await _channel.invokeMethod<Map>(
        'predict',
        _featureVectorToMap(f),
      );

      if (result == null) return _evaluateWithFallback(f);

      final label = result['risk_label'] as int;
      final threatProbability = (result['threat_probability'] as num)
          .toDouble();

      // Modello non disponibile lato Swift (label == -1)
      if (label == -1) {
        _modelAvailable = false;
        return _evaluateWithFallback(f);
      }

      final rawScore = threatProbability.clamp(0.0, 1.0);
      final smoothed = _smoother.update(rawScore);

      return RiskScore(
        value: rawScore,
        smoothedValue: smoothed,
        level: RiskScore.levelFromScore(smoothed),
        contributingFactors: [
          'ml_model(threat_prob=${rawScore.toStringAsFixed(3)})',
        ],
        timestamp: DateTime.now().toUtc(),
      );
    } on PlatformException catch (e) {
      // Errore nel canale → fallback silenzioso
      debugPrint('[MLRiskEngine] PlatformException: ${e.message}');
      _modelAvailable = false;
      return _evaluateWithFallback(f);
    }
  }

  RiskScore _evaluateWithFallback(FeatureVector f) {
    final score = _fallback.evaluate(f);
    // Aggiunge un tag per distinguere la sorgente in debug
    return RiskScore(
      value: score.value,
      smoothedValue: score.smoothedValue,
      level: score.level,
      contributingFactors: ['[fallback] ...${score.contributingFactors}'],
      timestamp: score.timestamp,
    );
  }

  Map<String, dynamic> _featureVectorToMap(FeatureVector f) => {
    // Vision
    'phone_detected': f.phoneDetected ? 1.0 : 0.0,
    'phone_confidence': f.phoneConfidence,
    'phone_persistence': f.phonePersistence,
    'phone_area_ratio': f.phoneAreaRatio,
    'phone_center_x': f.phoneCenterX,
    'phone_center_y': f.phoneCenterY,
    'face_detected': f.faceDetected ? 1.0 : 0.0,
    'face_count': f.faceCount.toDouble(),
    // IMU
    'accel_magnitude_mean': f.accelMagnitudeMean,
    'accel_magnitude_std': f.accelMagnitudeStd,
    'gyro_magnitude_mean': f.gyroMagnitudeMean,
    'gyro_magnitude_std': f.gyroMagnitudeStd,
    'tilt_angle': f.tiltAngle,
    'mag_magnitude_std': f.magMagnitudeStd,
    // Derived
    'is_stationary': f.isStationary ? 1.0 : 0.0,
    'tilt_in_photo_range': f.tiltInPhotoRange ? 1.0 : 0.0,
    'phone_strength': f.phoneStrength,
  };

  void reset() {
    _fallback.reset();
    _smoother.reset();
  }

  double get currentScore => _smoother.current;
  double get recentPeak => _smoother.recentPeak;
  bool get isUsingMLModel => _modelAvailable;
}
