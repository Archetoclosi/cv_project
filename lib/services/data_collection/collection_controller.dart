import 'dart:async';
import '../risk_engine/feature_vector.dart';
import '../risk_engine/risk_engine.dart';
import '../risk_engine/risk_score.dart';
import 'data_collector.dart';

/// Manages the data collection session.
///
/// Sits between your existing feature stream and the DataCollector.
/// The UI calls [labelThreat()] or [labelSafe()] to tag the LAST
/// N seconds of buffered samples with a label, then flushes them to disk.
class CollectionController {
  final RiskEngine engine;
  final DataCollector collector;

  /// How many recent FeatureVectors to label and save when the user taps.
  /// At 1 evaluation/sec, 3 = last 3 seconds of context.
  final int bufferSize;

  CollectionController({
    required this.engine,
    required this.collector,
    this.bufferSize = 3,
  });

  // Ring buffer of the most recent (feature, score) pairs
  final List<_BufferedEval> _buffer = [];

  // Stream of DatasetStats for the UI to observe
  final _statsController = StreamController<DatasetStats>.broadcast();
  Stream<DatasetStats> get statsStream => _statsController.stream;

  // Stream of RiskScore for the UI to observe (passthrough from engine)
  final _scoreController = StreamController<RiskScore>.broadcast();
  Stream<RiskScore> get scoreStream => _scoreController.stream;

  bool _initialized = false;

  Future<void> init() async {
    await collector.init();
    _initialized = true;
    // Emit initial stats
    _statsController.add(await collector.getStats());
  }

  /// Call this every time you receive a new FeatureVector from your pipeline.
  void onFeatures(FeatureVector features) {
    assert(_initialized, 'Call init() before onFeatures()');

    final score = engine.evaluate(features);
    _scoreController.add(score);

    // Maintain ring buffer
    _buffer.add(_BufferedEval(features: features, score: score));
    if (_buffer.length > bufferSize) _buffer.removeAt(0);
  }

  /// Label the buffered samples as THREAT and flush to CSV.
  Future<void> labelThreat({String? notes}) => _flush(isThreat: true, notes: notes);

  /// Label the buffered samples as SAFE and flush to CSV.
  Future<void> labelSafe({String? notes}) => _flush(isThreat: false, notes: notes);

  Future<void> _flush({required bool isThreat, String? notes}) async {
    if (_buffer.isEmpty) return;

    for (final eval in List.of(_buffer)) {
      await collector.save(LabeledSample(
        features: eval.features,
        isThreat: isThreat,
        ruleBasedScore: eval.score.value,
        timestamp: eval.score.timestamp,
        notes: notes,
      ));
    }

    _buffer.clear();

    // Emit updated stats
    _statsController.add(await collector.getStats());
  }

  Future<String> getFilePath() => collector.getFilePath();

  void dispose() {
    _statsController.close();
    _scoreController.close();
  }
}

class _BufferedEval {
  final FeatureVector features;
  final RiskScore score;
  const _BufferedEval({required this.features, required this.score});
}
