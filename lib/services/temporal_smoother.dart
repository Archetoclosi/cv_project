/// Temporal smoother for the raw risk score.
///
/// Uses an asymmetric exponential moving average (EMA):
/// - Fast rise: spikes propagate quickly (security-sensitive direction).
/// - Slow decay: score decreases gradually to avoid flickering.
///
/// Additionally exposes a [recentPeak] for the last N seconds,
/// so the UI can show "recent alert" indicators.
class TemporalSmoother {
  /// Alpha for rising signal (high α = reacts fast). Recommended: 0.6 – 0.8
  final double alphaRise;

  /// Alpha for falling signal (low α = decays slowly). Recommended: 0.1 – 0.25
  final double alphaDecay;

  /// How many recent raw values to keep for peak detection.
  final int peakWindowSize;

  double _smoothed = 0.0;
  final List<double> _recentValues = [];

  TemporalSmoother({
    this.alphaRise = 0.70,
    this.alphaDecay = 0.15,
    this.peakWindowSize = 10,
  });

  /// Feed a new raw score and get the smoothed value back.
  double update(double rawScore) {
    // Asymmetric EMA
    final alpha = rawScore > _smoothed ? alphaRise : alphaDecay;
    _smoothed = alpha * rawScore + (1.0 - alpha) * _smoothed;
    _smoothed = _smoothed.clamp(0.0, 1.0);

    // Maintain rolling window for peak detection
    _recentValues.add(rawScore);
    if (_recentValues.length > peakWindowSize) {
      _recentValues.removeAt(0);
    }

    return _smoothed;
  }

  /// Current smoothed value.
  double get current => _smoothed;

  /// Maximum raw score seen in the recent window.
  double get recentPeak =>
      _recentValues.isEmpty ? 0.0 : _recentValues.reduce((a, b) => a > b ? a : b);

  /// Reset smoother state (e.g. when the photo view is closed).
  void reset() {
    _smoothed = 0.0;
    _recentValues.clear();
  }
}
