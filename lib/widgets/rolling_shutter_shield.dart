import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum RollingShutterAggressiveness { low, medium, high }

/// Disrupts rolling-shutter camera capture by scrolling translucent bands
/// at speeds matching common sensor scan rates (8–33 ms per frame).
///
/// Imperceptible to the human eye; distorts photos taken of the screen.
class RollingShutterShield extends StatefulWidget {
  final bool enabled;
  final RollingShutterAggressiveness aggressiveness;
  final bool debug;
  final Widget child;

  const RollingShutterShield({
    super.key,
    this.enabled = true,
    this.aggressiveness = RollingShutterAggressiveness.medium,
    this.debug = false,
    required this.child,
  });

  @override
  State<RollingShutterShield> createState() => _RollingShutterShieldState();
}

class _BandSet {
  final Duration period;
  final int bandCount;
  final double bandHeightFraction; // fraction of screen height

  const _BandSet({
    required this.period,
    required this.bandCount,
    required this.bandHeightFraction,
  });
}

const _bandSetA = _BandSet(
  period: Duration(milliseconds: 8),
  bandCount: 3,
  bandHeightFraction: 0.03,
);

const _bandSetB = _BandSet(
  period: Duration(milliseconds: 15),
  bandCount: 3,
  bandHeightFraction: 0.03,
);

const _bandSetC = _BandSet(
  period: Duration(milliseconds: 25),
  bandCount: 4,
  bandHeightFraction: 0.025,
);

const _bandSetD = _BandSet(
  period: Duration(milliseconds: 33),
  bandCount: 4,
  bandHeightFraction: 0.04,
);

class _RollingShutterShieldState extends State<RollingShutterShield>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  double _frameTimeMs = 0;
  Duration _lastFrameTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.enabled) _ticker.start();
  }

  @override
  void didUpdateWidget(RollingShutterShield oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_ticker.isActive) {
      _elapsed = Duration.zero;
      _lastFrameTime = Duration.zero;
      _ticker.start();
    } else if (!widget.enabled && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    _frameTimeMs = (elapsed - _lastFrameTime).inMicroseconds / 1000.0;
    _lastFrameTime = elapsed;
    _elapsed = elapsed;
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  List<_BandSet> get _activeBandSets {
    switch (widget.aggressiveness) {
      case RollingShutterAggressiveness.low:
        return const [_bandSetA];
      case RollingShutterAggressiveness.medium:
        return const [_bandSetA, _bandSetB, _bandSetC];
      case RollingShutterAggressiveness.high:
        return const [_bandSetA, _bandSetB, _bandSetC, _bandSetD];
    }
  }

  double get _opacity {
    switch (widget.aggressiveness) {
      case RollingShutterAggressiveness.low:
        return 0.08;
      case RollingShutterAggressiveness.medium:
        return 0.12;
      case RollingShutterAggressiveness.high:
        return 0.15;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.enabled)
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _BandPainter(
                  elapsed: _elapsed,
                  bandSets: _activeBandSets,
                  opacity: _opacity,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        if (widget.enabled && widget.debug) _buildDebugOverlay(),
      ],
    );
  }

  Widget _buildDebugOverlay() {
    final sets = _activeBandSets;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 50,
      left: 8,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rolling Shutter Debug',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Frame: ${_frameTimeMs.toStringAsFixed(1)} ms',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              Text(
                'Opacity: $_opacity',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              Text(
                'Level: ${widget.aggressiveness.name}',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              const SizedBox(height: 4),
              for (int i = 0; i < sets.length; i++)
                Text(
                  'Set ${String.fromCharCode(65 + i)}: '
                  '${sets[i].period.inMilliseconds}ms, '
                  '${sets[i].bandCount} bands, '
                  '${(sets[i].bandHeightFraction * 100).toStringAsFixed(1)}%h',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandPainter extends CustomPainter {
  final Duration elapsed;
  final List<_BandSet> bandSets;
  final double opacity;

  _BandPainter({
    required this.elapsed,
    required this.bandSets,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final elapsedUs = elapsed.inMicroseconds;

    for (final set in bandSets) {
      final periodUs = set.period.inMicroseconds;
      if (periodUs == 0) continue;

      final progress = (elapsedUs % periodUs) / periodUs;
      final bandHeight = size.height * set.bandHeightFraction;

      // White bands — visible against dark backgrounds
      paint.color = Colors.white.withValues(alpha: opacity);

      for (int i = 0; i < set.bandCount; i++) {
        final spacing = 1.0 / set.bandCount;
        final baseY = (progress + spacing * i) % 1.0;
        final y = baseY * size.height;

        canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, bandHeight),
          paint,
        );

        // Wrap band when it crosses the bottom edge
        if (y + bandHeight > size.height) {
          canvas.drawRect(
            Rect.fromLTWH(0, 0, size.width, (y + bandHeight) - size.height),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.elapsed != elapsed;
}
