import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of an update check.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.hasUpdate,
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    this.error,
  });

  final bool   hasUpdate;
  final String latestVersion;
  final String currentVersion;
  final String releaseUrl;
  final String? error;

  /// Human-friendly label, e.g. "v1.2.0".
  String get latestTag  => latestVersion.startsWith('v') ? latestVersion : 'v$latestVersion';
  String get currentTag => currentVersion.startsWith('v') ? currentVersion : 'v$currentVersion';
}

/// Singleton service that checks the GitHub releases API for a newer version.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _repoOwner = 'jafanlim';
  static const String _repoName  = 'setall';
  static const String _apiUrl    =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  /// Checks GitHub for a new release. Returns an [UpdateCheckResult].
  /// Never throws — returns an error result on failure.
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // e.g. "1.1.0"

      final response = await http
          .get(Uri.parse(_apiUrl), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          hasUpdate:      false,
          latestVersion:  current,
          currentVersion: current,
          releaseUrl:     _fallbackUrl,
          error:          'HTTP ${response.statusCode}',
        );
      }

      final json        = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName     = (json['tag_name'] as String? ?? '').replaceFirst('v', '');
      final htmlUrl     = json['html_url'] as String? ?? _fallbackUrl;
      final hasUpdate   = _isNewer(tagName, current);

      return UpdateCheckResult(
        hasUpdate:      hasUpdate,
        latestVersion:  tagName,
        currentVersion: current,
        releaseUrl:     htmlUrl,
      );
    } catch (e) {
      debugPrint('[UpdateService] checkForUpdate error: $e');
      final info = await PackageInfo.fromPlatform().catchError((_) =>
          PackageInfo(appName: '', packageName: '', version: '0.0.0', buildNumber: ''));
      return UpdateCheckResult(
        hasUpdate:      false,
        latestVersion:  info.version,
        currentVersion: info.version,
        releaseUrl:     _fallbackUrl,
        error:          e.toString(),
      );
    }
  }

  /// Opens the release page in the system browser.
  Future<void> openReleasePage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static String get _fallbackUrl =>
      'https://github.com/$_repoOwner/$_repoName/releases';

  /// Returns true if [remote] is strictly newer than [local].
  /// Both are dotted-integer strings like "1.2.3".
  static bool _isNewer(String remote, String local) {
    try {
      final r = _parse(remote);
      final l = _parse(local);
      for (var i = 0; i < 3; i++) {
        if (r[i] > l[i]) return true;
        if (r[i] < l[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static List<int> _parse(String v) {
    final clean = v.replaceFirst('v', '');
    final parts = clean.split('.');
    return [
      int.tryParse(parts.isNotEmpty  ? parts[0] : '0') ?? 0,
      int.tryParse(parts.length > 1  ? parts[1] : '0') ?? 0,
      int.tryParse(parts.length > 2  ? parts[2] : '0') ?? 0,
    ];
  }
}
