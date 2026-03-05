import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../risk_engine/feature_vector.dart';
import '../risk_engine/risk_score.dart';

/// A single labeled sample for training data collection.
class LabeledSample {
  final FeatureVector features;
  final bool isThreat;
  final double ruleBasedScore; // score del rule-based engine al momento
  final DateTime timestamp;
  final String? notes;

  const LabeledSample({
    required this.features,
    required this.isThreat,
    required this.ruleBasedScore,
    required this.timestamp,
    this.notes,
  });
}

/// Collects labeled FeatureVector samples and persists them to a CSV file
/// in the app's Documents directory (accessible via iOS Files app).
class DataCollector {
  static const String _fileName = 'risk_engine_training_data.csv';

  static const List<String> _csvHeaders = [
    'timestamp',
    'is_threat',
    'rule_based_score',
    'rule_based_level',
    // Vision
    'phone_detected',
    'phone_confidence',
    'phone_persistence',
    'phone_area_ratio',
    'phone_center_x',
    'phone_center_y',
    'face_detected',
    'face_count',
    // IMU
    'accel_magnitude_mean',
    'accel_magnitude_std',
    'gyro_magnitude_mean',
    'gyro_magnitude_std',
    'tilt_angle',
    'mag_magnitude_std',
    // Derived
    'is_stationary',
    'tilt_in_photo_range',
    'phone_strength',
    // Notes
    'notes',
  ];

  int _sessionSampleCount = 0;
  File? _file;

  /// Total samples written in this session.
  int get sessionSampleCount => _sessionSampleCount;

  /// Initialize the collector and ensure the CSV file exists with headers.
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/$_fileName');

    // Write headers only if file doesn't exist yet
    if (!await _file!.exists()) {
      await _file!.writeAsString('${_csvHeaders.join(',')}\n');
    }
  }

  /// Save a labeled sample to the CSV file.
  Future<void> save(LabeledSample sample) async {
    assert(_file != null, 'Call init() before save()');

    final f = sample.features;
    final row = [
      sample.timestamp.toIso8601String(),
      sample.isThreat ? '1' : '0',
      sample.ruleBasedScore.toStringAsFixed(4),
      RiskScore.levelFromScore(sample.ruleBasedScore).label,
      // Vision
      f.phoneDetected ? '1' : '0',
      f.phoneConfidence.toStringAsFixed(4),
      f.phonePersistence.toStringAsFixed(4),
      f.phoneAreaRatio.toStringAsFixed(4),
      f.phoneCenterX.toStringAsFixed(4),
      f.phoneCenterY.toStringAsFixed(4),
      f.faceDetected ? '1' : '0',
      f.faceCount.toString(),
      // IMU
      f.accelMagnitudeMean.toStringAsFixed(4),
      f.accelMagnitudeStd.toStringAsFixed(4),
      f.gyroMagnitudeMean.toStringAsFixed(4),
      f.gyroMagnitudeStd.toStringAsFixed(4),
      f.tiltAngle.toStringAsFixed(4),
      f.magMagnitudeStd.toStringAsFixed(4),
      // Derived
      f.isStationary ? '1' : '0',
      f.tiltInPhotoRange ? '1' : '0',
      f.phoneStrength.toStringAsFixed(4),
      // Notes (escape commas)
      '"${(sample.notes ?? '').replaceAll('"', '""')}"',
    ];

    await _file!.writeAsString(
      '${row.join(',')}\n',
      mode: FileMode.append,
    );

    _sessionSampleCount++;
  }

  /// Returns the full path of the CSV file (for sharing / debug UI).
  Future<String> getFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_fileName';
  }

  /// Returns stats about the current CSV (total rows, threat/safe split).
  Future<DatasetStats> getStats() async {
    assert(_file != null, 'Call init() before getStats()');
    if (!await _file!.exists()) return DatasetStats.empty();

    final lines = await _file!.readAsLines();
    if (lines.length <= 1) return DatasetStats.empty(); // only header

    final dataLines = lines.skip(1); // skip header
    int threats = 0, safes = 0;

    for (final line in dataLines) {
      if (line.trim().isEmpty) continue;
      final cols = line.split(',');
      if (cols.length < 2) continue;
      cols[1].trim() == '1' ? threats++ : safes++;
    }

    return DatasetStats(
      total: threats + safes,
      threats: threats,
      safes: safes,
    );
  }
}

class DatasetStats {
  final int total;
  final int threats;
  final int safes;

  const DatasetStats({
    required this.total,
    required this.threats,
    required this.safes,
  });

  factory DatasetStats.empty() =>
      const DatasetStats(total: 0, threats: 0, safes: 0);

  /// Balance ratio: 1.0 = perfectly balanced, < 0.5 = very unbalanced.
  double get balanceRatio =>
      total == 0 ? 0.0 : (threats < safes ? threats / safes : safes / threats);

  bool get isBalanced => balanceRatio >= 0.4;

  @override
  String toString() =>
      'DatasetStats(total=$total, threats=$threats, safes=$safes, '
      'balance=${(balanceRatio * 100).toStringAsFixed(0)}%)';
}
