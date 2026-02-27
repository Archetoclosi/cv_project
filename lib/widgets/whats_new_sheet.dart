import 'package:flutter/material.dart';
import '../services/changelog_service.dart';

class WhatsNewSheet extends StatelessWidget {
  final String version;
  final List<String> entries;

  const WhatsNewSheet({
    super.key,
    required this.version,
    required this.entries,
  });

  // ── Auto: show only when version is new. Marks it as seen before showing so
  //    even if the user swipes it away without tapping "Got it" it won't
  //    reappear on the next launch.
  static Future<void> showIfNew(BuildContext context) async {
    try {
      final service = ChangelogService();
      final shouldShow = await service.shouldShowAutomatically();
      if (!shouldShow) return;

      // Mark first so a force-quit after display doesn't retrigger it.
      await service.markCurrentVersionSeen();

      final version = await service.getCurrentVersion();
      final entries = service.getEntriesForVersion(version);

      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => WhatsNewSheet(version: version, entries: entries),
      );
    } catch (_) {
      // Changelog is non-critical — silently swallow errors.
    }
  }

  // ── Manual: always shows, never touches SharedPreferences so it doesn't
  //    interfere with the "already seen" logic for the automatic check.
  static Future<void> showManually(BuildContext context) async {
    final service = ChangelogService();
    final version = await service.getCurrentVersion();
    final entries = service.getEntriesForVersion(version);

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => WhatsNewSheet(version: version, entries: entries),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Version badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: primary.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Text(
              'v$version',
              style: TextStyle(
                color: primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            "What's New",
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          ...entries.map((entry) => _EntryRow(text: entry, accent: primary)),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Got it',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final String text;
  final Color accent;

  const _EntryRow({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
