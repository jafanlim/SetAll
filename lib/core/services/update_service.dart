import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

/// Result of an update check.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.hasUpdate,
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    this.downloadUrl,
    this.assetName,
    this.error,
  });

  final bool    hasUpdate;
  final String  latestVersion;
  final String  currentVersion;
  /// GitHub release HTML page (fallback if no direct asset found).
  final String  releaseUrl;
  /// Direct download URL for the platform-specific installer asset, if present.
  final String? downloadUrl;
  /// File name of the asset, e.g. "SetAll-macOS.dmg".
  final String? assetName;
  final String? error;

  /// Human-friendly label, e.g. "v1.2.0".
  String get latestTag  => latestVersion.startsWith('v') ? latestVersion : 'v$latestVersion';
  String get currentTag => currentVersion.startsWith('v') ? currentVersion : 'v$currentVersion';

  /// True when there is a direct downloadable asset for this platform.
  bool get hasDirectDownload => downloadUrl != null && downloadUrl!.isNotEmpty;
}

/// Phases of the in-app download/install flow.
enum UpdateDownloadState {
  idle,
  downloading,
  readyToInstall,
  error,
}

/// Snapshot of the download progress.
class UpdateDownloadProgress {
  const UpdateDownloadProgress({
    required this.state,
    this.received = 0,
    this.total = 0,
    this.localPath,
    this.errorMessage,
  });

  final UpdateDownloadState state;
  final int    received;
  final int    total;
  /// Set once download completes successfully.
  final String? localPath;
  final String? errorMessage;

  double get fraction => (total > 0) ? (received / total).clamp(0.0, 1.0) : 0.0;

  UpdateDownloadProgress copyWith({
    UpdateDownloadState? state,
    int? received,
    int? total,
    String? localPath,
    String? errorMessage,
  }) => UpdateDownloadProgress(
    state:        state        ?? this.state,
    received:     received     ?? this.received,
    total:        total        ?? this.total,
    localPath:    localPath    ?? this.localPath,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Singleton service that checks for, downloads, and launches updates.
///
/// Flow:
///   1. [checkForUpdate]  – hits GitHub API, extracts platform asset URL.
///   2. [downloadUpdate]  – streams download progress to [downloadProgress].
///   3. [launchInstaller] – opens the downloaded file, then exits the app.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _repoOwner = 'jafanlim';
  static const String _repoName  = 'setall';
  static const String _apiUrl    =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  // Current download progress — listened to by the banner widget.
  UpdateDownloadProgress _progress = const UpdateDownloadProgress(
    state: UpdateDownloadState.idle,
  );
  final List<void Function(UpdateDownloadProgress)> _listeners = [];

  UpdateDownloadProgress get downloadProgress => _progress;

  void addProgressListener(void Function(UpdateDownloadProgress) fn) =>
      _listeners.add(fn);
  void removeProgressListener(void Function(UpdateDownloadProgress) fn) =>
      _listeners.remove(fn);

  void _emit(UpdateDownloadProgress p) {
    _progress = p;
    for (final fn in List.of(_listeners)) { fn(p); }
  }

  // ---------------------------------------------------------------------------
  // 1. Check
  // ---------------------------------------------------------------------------

  /// Checks GitHub for a new release. Returns an [UpdateCheckResult].
  /// Never throws — returns an error result on failure.
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final info    = await PackageInfo.fromPlatform();
      final current = info.version;

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

      final body        = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName     = (body['tag_name'] as String? ?? '').replaceFirst('v', '');
      final htmlUrl     = body['html_url'] as String? ?? _fallbackUrl;
      final hasUpdate   = _isNewer(tagName, current);

      // Extract platform-matching asset URL from the assets list.
      String? downloadUrl;
      String? assetName;
      if (hasUpdate) {
        final assets = body['assets'] as List<dynamic>? ?? [];
        final platformSuffix = _platformAssetSuffix();
        for (final a in assets) {
          final map  = a as Map<String, dynamic>;
          final name = map['name'] as String? ?? '';
          if (name.toLowerCase().contains(platformSuffix)) {
            downloadUrl = map['browser_download_url'] as String?;
            assetName   = name;
            break;
          }
        }
      }

      return UpdateCheckResult(
        hasUpdate:      hasUpdate,
        latestVersion:  tagName,
        currentVersion: current,
        releaseUrl:     htmlUrl,
        downloadUrl:    downloadUrl,
        assetName:      assetName,
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

  // ---------------------------------------------------------------------------
  // 2. Download
  // ---------------------------------------------------------------------------

  /// Downloads the installer asset for [result] to the system temp directory,
  /// streaming progress via [downloadProgress] / listeners.
  ///
  /// If [result.hasDirectDownload] is false, falls back to opening the browser.
  Future<void> downloadUpdate(UpdateCheckResult result) async {
    if (!result.hasDirectDownload) {
      await openReleasePage(result.releaseUrl);
      return;
    }

    _emit(const UpdateDownloadProgress(state: UpdateDownloadState.downloading));

    try {
      final tmpDir   = await getTemporaryDirectory();
      final fileName = result.assetName ?? _defaultAssetName();
      final destFile = File('${tmpDir.path}${Platform.pathSeparator}$fileName');

      final request  = http.Request('GET', Uri.parse(result.downloadUrl!));
      final streamed = await http.Client().send(request);
      final total    = streamed.contentLength ?? 0;
      int received   = 0;

      final sink = destFile.openWrite();
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        _emit(UpdateDownloadProgress(
          state:    UpdateDownloadState.downloading,
          received: received,
          total:    total,
        ));
      }
      await sink.flush();
      await sink.close();

      _emit(UpdateDownloadProgress(
        state:     UpdateDownloadState.readyToInstall,
        received:  received,
        total:     total,
        localPath: destFile.path,
      ));
    } catch (e) {
      debugPrint('[UpdateService] downloadUpdate error: $e');
      _emit(UpdateDownloadProgress(
        state:        UpdateDownloadState.error,
        errorMessage: e.toString(),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Launch + quit
  // ---------------------------------------------------------------------------

  /// Opens the downloaded installer file, then terminates the running app so
  /// the installer can replace the binary without file-lock conflicts.
  Future<void> launchInstaller(String localPath) async {
    try {
      if (Platform.isMacOS) {
        // 'open' launches .dmg / .app / .pkg and returns immediately.
        await Process.start('open', [localPath],
            mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        // /VERYSILENT  — no UI, no prompts.
        // /NORESTART   — installer won't reboot the machine.
        // /CLOSEAPPLICATIONS — kills the running SetAll process so the
        //                      installer can overwrite the EXE.
        await Process.start(
          localPath,
          ['/VERYSILENT', '/NORESTART', '/CLOSEAPPLICATIONS'],
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] launchInstaller error: $e');
      // Last-resort fallback — open the releases page.
      await openReleasePage(_fallbackUrl);
      return;
    }
    // Give the OS ~500 ms to start the installer before we quit.
    await Future.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Opens the release page in the system browser (fallback).
  Future<void> openReleasePage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Resets download state back to idle (e.g. on banner dismiss).
  void resetDownload() {
    _emit(const UpdateDownloadProgress(state: UpdateDownloadState.idle));
  }

  static String get _fallbackUrl =>
      'https://github.com/$_repoOwner/$_repoName/releases';

  /// Returns the lowercase suffix used to pick the right asset from a release.
  static String _platformAssetSuffix() {
    if (Platform.isMacOS)   return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  static String _defaultAssetName() {
    if (Platform.isMacOS)   return 'SetAll-macOS.dmg';
    if (Platform.isWindows) return 'SetAll-Windows.exe';
    return 'SetAll-Linux.tar.gz';
  }

  /// Returns true if [remote] is strictly newer than [local].
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
      int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
    ];
  }
}
