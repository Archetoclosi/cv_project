import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/data_collection/collection_controller.dart';
import '../services/data_collection/data_collector.dart';

/// A debug overlay widget that renders on top of the ProtectedPhotoView
/// during data collection sessions.
///
/// Shows:
///  - Live risk score from the engine
///  - THREAT / SAFE label buttons
///  - Running dataset stats (total, balance)
///  - Export button
///
/// Usage: wrap only in debug builds.
/// ```dart
/// if (kDebugMode)
///   CollectionOverlay(controller: _collectionController)
/// ```
class CollectionOverlay extends StatefulWidget {
  final CollectionController controller;

  const CollectionOverlay({super.key, required this.controller});

  @override
  State<CollectionOverlay> createState() => _CollectionOverlayState();
}

class _CollectionOverlayState extends State<CollectionOverlay> {
  DatasetStats _stats = DatasetStats.empty();
  double _currentScore = 0.0;
  String? _lastAction;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.statsStream.listen((stats) {
      if (mounted) setState(() => _stats = stats);
    });
    widget.controller.scoreStream.listen((score) {
      if (mounted) setState(() => _currentScore = score.smoothedValue);
    });
  }

  void _onLabel(bool isThreat) async {
    await (isThreat
        ? widget.controller.labelThreat()
        : widget.controller.labelSafe());

    _feedbackTimer?.cancel();
    setState(() => _lastAction = isThreat ? '✓ THREAT saved' : '✓ SAFE saved');
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _lastAction = null);
    });
  }

  void _onExport() async {
    final path = await widget.controller.getFilePath();
    await Share.shareXFiles([XFile(path)], subject: 'RiskEngine Training Data');
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xF01C1C1E), // iOS dark sheet
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildLabelButtons(),
              if (_lastAction != null) ...[
                const SizedBox(height: 8),
                _buildFeedback(),
              ],
              const SizedBox(height: 12),
              _buildStats(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final pct = (_currentScore * 100).toStringAsFixed(0);
    final color = _scoreColor(_currentScore);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          'Risk: $pct%',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const Spacer(),
        Text(
          'DATA COLLECTION',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLabelButtons() {
    return Row(
      children: [
        Expanded(
          child: _LabelButton(
            label: '⚠ THREAT',
            color: const Color(0xFFFF3B30),
            onTap: () => _onLabel(true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _LabelButton(
            label: '✓ SAFE',
            color: const Color(0xFF34C759),
            onTap: () => _onLabel(false),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedback() {
    return Text(
      _lastAction!,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildStats() {
    final balanceColor = _stats.isBalanced
        ? const Color(0xFF34C759)
        : const Color(0xFFFF9F0A);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _StatChip(label: 'Total', value: '${_stats.total}'),
        _StatChip(
          label: 'Threats',
          value: '${_stats.threats}',
          color: const Color(0xFFFF3B30),
        ),
        _StatChip(
          label: 'Safe',
          value: '${_stats.safes}',
          color: const Color(0xFF34C759),
        ),
        _StatChip(
          label: 'Balance',
          value: '${(_stats.balanceRatio * 100).toStringAsFixed(0)}%',
          color: balanceColor,
        ),
        GestureDetector(
          onTap: _onExport,
          child: const Icon(Icons.ios_share, color: Colors.white54, size: 20),
        ),
      ],
    );
  }

  Color _scoreColor(double score) {
    if (score < 0.25) return const Color(0xFF34C759);
    if (score < 0.55) return const Color(0xFFFF9F0A);
    if (score < 0.80) return const Color(0xFFFF6B35);
    return const Color(0xFFFF3B30);
  }
}

class _LabelButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _LabelButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    this.color = Colors.white60,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }
}
