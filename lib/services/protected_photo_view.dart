import 'dart:async';
import 'package:flutter/material.dart';

import 'risk_engine/feature_vector.dart';
import 'risk_engine/risk_engine.dart';
import 'risk_engine/risk_score.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Integration example
//
// Assumes you already have:
//   - Stream<FeatureVector> featureStream   (your existing pipeline)
//
// This file shows how to wire everything together and drive a UI overlay.
// ─────────────────────────────────────────────────────────────────────────────

class ProtectedPhotoView extends StatefulWidget {
  /// The stream of feature vectors produced by your existing sensor pipeline.
  /// If null, a default empty stream is used (no risk overlay activity).
  final Stream<FeatureVector>? featureStream;

  /// The image/content to protect.
  final Widget child;

  const ProtectedPhotoView({
    super.key,
    this.featureStream,
    required this.child,
  });

  @override
  State<ProtectedPhotoView> createState() => _ProtectedPhotoViewState();
}

class _ProtectedPhotoViewState extends State<ProtectedPhotoView>
    with SingleTickerProviderStateMixin {

  final _engine = RiskEngine();
  late final StreamSubscription<FeatureVector> _sub;

  RiskScore _score = RiskScore.safe();
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    final stream = widget.featureStream ?? const Stream<FeatureVector>.empty();

    _sub = stream.listen((features) {
      final score = _engine.evaluate(features);
      setState(() => _score = score);

      // Pulse animation on elevated/critical
      if (score.level == RiskLevel.elevated || score.level == RiskLevel.critical) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _engine.reset();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Protected content ──────────────────────────────────────────────
        // Apply blur/hide based on risk level
        _score.level == RiskLevel.critical
            ? _buildHiddenContent()
            : widget.child,

        // ── Risk overlay ───────────────────────────────────────────────────
        _RiskOverlay(score: _score, pulseController: _pulseController),
      ],
    );
  }

  Widget _buildHiddenContent() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Icon(Icons.visibility_off, color: Colors.white54, size: 48),
      ),
    );
  }
}

// ─── Risk Overlay Widget ──────────────────────────────────────────────────────

class _RiskOverlay extends StatelessWidget {
  final RiskScore score;
  final AnimationController pulseController;

  const _RiskOverlay({required this.score, required this.pulseController});

  @override
  Widget build(BuildContext context) {
    if (score.level == RiskLevel.safe) return const SizedBox.shrink();

    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: pulseController,
          builder: (context, child) {
            final pulse = score.level == RiskLevel.critical
                ? 0.7 + 0.3 * pulseController.value
                : 1.0;
            return Opacity(
              opacity: pulse,
              child: child,
            );
          },
          child: _RiskBanner(score: score),
        ),
      ),
    );
  }
}

class _RiskBanner extends StatelessWidget {
  final RiskScore score;
  const _RiskBanner({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score.level.color;
    final pct = (score.smoothedValue * 100).toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12)],
      ),
      child: Row(
        children: [
          Icon(_iconForLevel(score.level), color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${score.level.label} — $pct% risk',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          // Debug: show top contributing factor
          if (score.contributingFactors.isNotEmpty)
            Text(
              score.contributingFactors.first.split(' ').first,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForLevel(RiskLevel level) {
    switch (level) {
      case RiskLevel.safe:     return Icons.shield_outlined;
      case RiskLevel.caution:  return Icons.warning_amber_outlined;
      case RiskLevel.elevated: return Icons.warning_rounded;
      case RiskLevel.critical: return Icons.gpp_bad_rounded;
    }
  }
}
