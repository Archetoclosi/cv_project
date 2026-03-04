import 'package:flutter/material.dart';

/// Risk level classification derived from the raw score.
enum RiskLevel {
  /// score < 0.25 — No suspicious signals.
  safe,

  /// score 0.25 – 0.55 — Weak or ambiguous signals, monitor.
  caution,

  /// score 0.55 – 0.80 — Multiple correlated signals, likely threat.
  elevated,

  /// score > 0.80 — High-confidence threat, act immediately.
  critical,
}

extension RiskLevelX on RiskLevel {
  String get label {
    switch (this) {
      case RiskLevel.safe:     return 'SAFE';
      case RiskLevel.caution:  return 'CAUTION';
      case RiskLevel.elevated: return 'ELEVATED';
      case RiskLevel.critical: return 'CRITICAL';
    }
  }

  Color get color {
    switch (this) {
      case RiskLevel.safe:     return const Color(0xFF34C759); // iOS green
      case RiskLevel.caution:  return const Color(0xFFFF9F0A); // iOS orange
      case RiskLevel.elevated: return const Color(0xFFFF6B35); // deep orange
      case RiskLevel.critical: return const Color(0xFFFF3B30); // iOS red
    }
  }

  /// Opacity to apply to the content blur/overlay.
  double get overlayOpacity {
    switch (this) {
      case RiskLevel.safe:     return 0.0;
      case RiskLevel.caution:  return 0.15;
      case RiskLevel.elevated: return 0.40;
      case RiskLevel.critical: return 0.75;
    }
  }
}

/// Output of the Risk Engine for a single evaluation window.
class RiskScore {
  /// Raw probability score. [0.0 – 1.0]
  final double value;

  /// Smoothed score after temporal filtering. [0.0 – 1.0]
  final double smoothedValue;

  /// Discrete classification derived from [smoothedValue].
  final RiskLevel level;

  /// Human-readable explanation of which signals contributed.
  /// Useful for debugging and (optionally) showing to the user.
  final List<String> contributingFactors;

  /// UTC timestamp of this evaluation.
  final DateTime timestamp;

  const RiskScore({
    required this.value,
    required this.smoothedValue,
    required this.level,
    required this.contributingFactors,
    required this.timestamp,
  });

  /// Convenience constructor for a zero-risk score.
  factory RiskScore.safe() => RiskScore(
        value: 0.0,
        smoothedValue: 0.0,
        level: RiskLevel.safe,
        contributingFactors: [],
        timestamp: DateTime.now().toUtc(),
      );

  static RiskLevel levelFromScore(double score) {
    if (score < 0.25) return RiskLevel.safe;
    if (score < 0.55) return RiskLevel.caution;
    if (score < 0.80) return RiskLevel.elevated;
    return RiskLevel.critical;
  }

  @override
  String toString() =>
      'RiskScore(value=${value.toStringAsFixed(3)}, '
      'smoothed=${smoothedValue.toStringAsFixed(3)}, '
      'level=${level.label}, factors=$contributingFactors)';
}
