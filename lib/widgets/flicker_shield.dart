import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Overlays a high-frequency noise pattern on [child] to disrupt camera capture.
///
/// The noise flickers at ~60 Hz (randomised ±10 Hz) with opacity 0.3.
/// Imperceptible to the human eye; disruptive for camera sensors.
class FlickerShield extends StatefulWidget {
  final Widget child;

  const FlickerShield({super.key, required this.child});

  @override
  State<FlickerShield> createState() => _FlickerShieldState();
}

class _FlickerShieldState extends State<FlickerShield>
    with SingleTickerProviderStateMixin {
  static const int _noiseVariants = 4;
  static const int _gridCols = 24;
  static const int _gridRows = 36;
  static const double _overlayOpacity = 0.3;
  static const double _baseFrequencyHz = 60.0;
  static const double _frequencyJitterHz = 10.0;
  static const double _minFrequencyHz = 50.0;

  late final Ticker _ticker;
  final _random = Random();

  /// Pre-generated noise seeds — each produces a different pattern.
  late final List<int> _noiseSeeds;

  int _currentVariant = 0;
  Duration _lastToggle = Duration.zero;
  late Duration _currentInterval;
  bool _showNoise = false;

  @override
  void initState() {
    super.initState();
    _noiseSeeds = List.generate(_noiseVariants, (_) => _random.nextInt(1 << 32));
    _currentInterval = _randomInterval();
    _ticker = createTicker(_onTick)..start();
  }

  Duration _randomInterval() {
    final hz = max(
      _minFrequencyHz,
      _baseFrequencyHz + (_random.nextDouble() * 2 - 1) * _frequencyJitterHz,
    );
    return Duration(microseconds: (1e6 / hz).round());
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _lastToggle >= _currentInterval) {
      _lastToggle = elapsed;
      _showNoise = !_showNoise;
      if (_showNoise) {
        _currentVariant = (_currentVariant + 1) % _noiseVariants;
      }
      _currentInterval = _randomInterval();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        RepaintBoundary(
          child: Opacity(
            opacity: _showNoise ? _overlayOpacity : 0.0,
            child: CustomPaint(
              painter: _NoisePainter(
                seed: _noiseSeeds[_currentVariant],
                cols: _gridCols,
                rows: _gridRows,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoisePainter extends CustomPainter {
  final int seed;
  final int cols;
  final int rows;

  _NoisePainter({required this.seed, required this.cols, required this.rows});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        paint.color = Color.fromARGB(
          255,
          rng.nextInt(256),
          rng.nextInt(256),
          rng.nextInt(256),
        );
        canvas.drawRect(
          Rect.fromLTWH(c * cellW, r * cellH, cellW + 1, cellH + 1),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NoisePainter old) => old.seed != seed;
}
