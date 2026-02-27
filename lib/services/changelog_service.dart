import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChangelogService {
  static const String _lastSeenKey = 'whats_new_last_seen_version';

  // ─── Changelog ────────────────────────────────────────────────────────────
  // Add a new entry here with each release. Key = version from pubspec
  // (the part before '+', e.g. "1.0.0-alpha" for "1.0.0-alpha+1").
  static const Map<String, List<String>> _changelog = {
    '0.0.1-alpha': [
      'Persistent login with "Remember me"',
      'Patch Notes System'
    ],
  };
  // ──────────────────────────────────────────────────────────────────────────

  // Reads the version directly from the bundled pubspec.yaml so that
  // pre-release identifiers (-alpha, -beta, etc.) are never stripped by
  // platform tooling (iOS CFBundleShortVersionString, Android versionName).
  // Falls back to PackageInfo if the asset can't be read.
  Future<String> getCurrentVersion() async {
    try {
      final yaml = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(yaml);
      if (match != null) {
        // Keep pre-release suffix (-alpha etc.) but drop build number (+N).
        return match.group(1)!.split('+').first;
      }
    } catch (_) {}
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  Future<bool> shouldShowAutomatically() async {
    final version = await getCurrentVersion();
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getString(_lastSeenKey);
    return lastSeen != version;
  }

  Future<void> markCurrentVersionSeen() async {
    final version = await getCurrentVersion();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenKey, version);
  }

  List<String> getEntriesForVersion(String version) {
    // Strip build number in case it leaks through (e.g. "1.0.0-alpha+1" → "1.0.0-alpha")
    final key = version.split('+').first;
    if (_changelog.containsKey(key)) return _changelog[key]!;
    // Fall back to the most recent entry if the version isn't listed yet
    return _changelog.values.isNotEmpty ? _changelog.values.last : [];
  }
}
