import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/setall_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/setall_providers.dart';
import 'core/providers/theme_mode_provider.dart';
import 'core/services/update_service.dart';
import 'core/utils/scaling_utility.dart';
import 'data/local/local_database.dart';

// ---------------------------------------------------------------------------
// Update state — shared across app.dart and settings_screen.dart
// ---------------------------------------------------------------------------

final updateResultProvider =
    StateProvider<UpdateCheckResult?>((ref) => null);

class SetAllApp extends ConsumerStatefulWidget {
  const SetAllApp({super.key});

  @override
  ConsumerState<SetAllApp> createState() => _SetAllAppState();
}

class _SetAllAppState extends ConsumerState<SetAllApp> {
  StreamSubscription<AuthState>? _authSub;
  String? _lastUserId;
  bool _updateBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        _onAuthChange,
      );
    } catch (_) {
      // Supabase not configured (e.g. no credentials) — skip.
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _onAuthChange(AuthState state) async {
    final newUid = state.session?.user.id;

    // Handle all events that mean "we have a valid authenticated session":
    //   • signedIn       — fresh login
    //   • initialSession — cold start with a stored session (most common case)
    //   • tokenRefreshed — silent token renewal
    final isAuthenticatedEvent =
        state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.initialSession ||
        state.event == AuthChangeEvent.tokenRefreshed;

    if (isAuthenticatedEvent && newUid != null) {
      final isUserSwitch = _lastUserId != null && newUid != _lastUserId;
      final isFirstLogin  = _lastUserId == null;

      if (isUserSwitch) {
        // Push any unsynced local writes before wiping for the new user.
        try { await ref.read(syncServiceProvider).performFullSync(); } catch (_) {}
        // Different account — wipe SQLite and all provider caches.
        await _wipeSQLiteCache();
        _invalidateAllProviders();
      } else if (isFirstLogin) {
        // First login this session — invalidate caches only (no SQLite wipe).
        _invalidateAllProviders();
      }
      // Token refresh / session-restore with same user: do nothing extra —
      // the StreamController and its listeners stay intact.

      // Migrate any entries created under the anonymous device UUID to the
      // real Supabase user ID, then reset their synced_at so they get pushed.
      await _migrateDeviceUidToRealUid(newUid);

      _lastUserId = newUid;

      final sync = ref.read(syncServiceProvider);
      // subscribeToRealtime is idempotent — cancels existing channel/timer
      // before creating new ones. Safe to call on every token refresh.
      sync.subscribeToRealtime();
      unawaited(
        sync.performFullSync().then((_) {
          if (!mounted) return;
          ref.invalidate(balanceSummaryProvider);
          ref.invalidate(recentExpensesProvider);
        }),
      );
      // Check for updates once per session (first login / initial session).
      if (isFirstLogin) unawaited(_checkForUpdates());
    }

    // On sign-out always invalidate so the login screen starts clean.
    if (state.event == AuthChangeEvent.signedOut) {
      _lastUserId = null;
      _invalidateAllProviders();
      ref.read(syncServiceProvider).unsubscribeFromRealtime();
    }
  }

  /// Finds any local rows stamped with the anonymous device UUID and
  /// re-stamps them with the real Supabase [uid]. Also resets synced_at = NULL
  /// on rows that were permanently skipped (synced_at = -1) so the push
  /// retries them with the correct payer_id.
  Future<void> _migrateDeviceUidToRealUid(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceUid = prefs.getString('device_user_id');
      if (deviceUid == null || deviceUid.isEmpty || deviceUid == uid) return;

      final db = LocalDatabase.db;

      // Re-stamp expenses.
      final affected = await db.update(
        'expenses',
        {'payer_id': uid, 'synced_at': null},
        where: 'payer_id = ?',
        whereArgs: [deviceUid],
      );

      if (affected > 0) {
        debugPrint('[app] migrated $affected expense(s) from device UID $deviceUid → $uid');
        // Re-stamp splits for those expenses too.
        await db.rawUpdate(
          '''
          UPDATE splits SET synced_at = NULL
          WHERE expense_id IN (
            SELECT id FROM expenses WHERE payer_id = ?
          )
          ''',
          [uid],
        );
      }

      // Also un-blacklist any expenses/splits that were previously rejected
      // with RLS error (synced_at = -1) but now have the correct payer_id.
      await db.update(
        'expenses',
        {'synced_at': null},
        where: 'payer_id = ? AND synced_at = -1',
        whereArgs: [uid],
      );
      await db.rawUpdate(
        '''
        UPDATE splits SET synced_at = NULL
        WHERE synced_at = -1
          AND expense_id IN (SELECT id FROM expenses WHERE payer_id = ?)
        ''',
        [uid],
      );

      // Clear the device UUID so it is never reused after migration.
      await prefs.remove('device_user_id');
    } catch (e) {
      debugPrint('[app] _migrateDeviceUidToRealUid error (non-fatal): $e');
    }
  }

  Future<void> _wipeSQLiteCache() async {
    try {
      final db = LocalDatabase.db;
      await db.delete('splits');
      await db.delete('expenses');
      await db.delete('group_members');
      await db.delete('groups');
      await db.delete('profiles');
    } catch (_) {
      // Web mode — no SQLite, nothing to wipe.
    }
  }

  Future<void> _checkForUpdates() async {
    final result = await UpdateService.instance.checkForUpdate();
    if (!mounted) return;
    if (result.hasUpdate) {
      ref.read(updateResultProvider.notifier).state = result;
      setState(() => _updateBannerDismissed = false);
    }
  }

  void _invalidateAllProviders() {
    // Do NOT invalidate setAllRepositoryProvider — it owns the StreamController
    // that backs watchGroups()/watchGroupExpenses(). Destroying it kills all
    // active stream listeners and creates a new instance that notifySyncComplete()
    // can never reach.
    ref.invalidate(balanceSummaryProvider);
    ref.invalidate(baseCurrencyProvider);
    ref.invalidate(currentProfileProvider);
    ref.invalidate(myGroupsProvider);
    ref.invalidate(friendGroupsProvider);
    ref.invalidate(recentExpensesProvider);
  }

  static bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDesktop = _isDesktop;

    return MaterialApp.router(
      title: 'SetAll',
      debugShowCheckedModeBanner: false,
      theme: isDesktop ? SetAllTheme.desktopLight : SetAllTheme.light,
      darkTheme: isDesktop ? SetAllTheme.desktopDark : SetAllTheme.dark,
      themeMode: themeMode,
      routerConfig: AppRouter.create(),
      builder: (context, child) {
        // On desktop, pass the actual window size as the design size so every
        // .w / .h / .sp call is a 1:1 identity (no upscaling from mobile baseline).
        // Mobile keeps the 390×844 iPhone 16 Pro baseline.
        final designSize = isDesktop
            ? const Size(1440, 900)
            : const Size(ScalingUtility.designWidth, ScalingUtility.designHeight);

        final inner = child ?? const SizedBox.shrink();

        return ScreenUtilInit(
          designSize: designSize,
          minTextAdapt: !isDesktop,
          splitScreenMode: false,
          builder: (context, _) {
            ScalingUtility.init(context);
            final theme = Theme.of(context);
            final isMac = defaultTargetPlatform == TargetPlatform.macOS;
            final isWin = defaultTargetPlatform == TargetPlatform.windows;

            // ── Full-width title-bar fringe (desktop only) ────────────────
            // Sits above every screen — shell tabs AND push routes — so
            // nothing ever collides with window controls / traffic lights.
            Widget content = inner;
            if (isMac || isWin) {
              content = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AppTitleBar(isMac: isMac),
                  Expanded(child: inner),
                ],
              );
            }

            // ── Update banner (non-intrusive, desktop + mobile) ─────────
            final updateResult = ref.watch(updateResultProvider);
            final showBanner   = updateResult != null &&
                updateResult.hasUpdate &&
                !_updateBannerDismissed;

            Widget root = content;
            if (showBanner) {
              root = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _UpdateBanner(
                    result: updateResult,
                    onDismiss: () => setState(() => _updateBannerDismissed = true),
                  ),
                  Expanded(child: content),
                ],
              );
            }

            return Container(
              color: theme.colorScheme.surface,
              child: root,
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Update available banner — three phases:
//   idle          → "Update available  [Download & Install]  [✕]"
//   downloading   → progress bar + percentage
//   readyToInstall→ "Ready  [Install Now & Quit]  [✕]"
//   error         → error text + [Retry]
// ---------------------------------------------------------------------------

class _UpdateBanner extends StatefulWidget {
  const _UpdateBanner({required this.result, required this.onDismiss});

  final UpdateCheckResult result;
  final VoidCallback onDismiss;

  @override
  State<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<_UpdateBanner> {
  static const _kBg     = Color(0xFF1E3A5F);
  static const _kAccent = Color(0xFF38BDF8);
  static const _kGreen  = Color(0xFF4ADE80);
  static const _kRed    = Color(0xFFF87171);
  static const _kText   = Color(0xFFE0F2FE);

  late UpdateDownloadProgress _prog;

  @override
  void initState() {
    super.initState();
    _prog = UpdateService.instance.downloadProgress;
    UpdateService.instance.addProgressListener(_onProgress);
  }

  @override
  void dispose() {
    UpdateService.instance.removeProgressListener(_onProgress);
    super.dispose();
  }

  void _onProgress(UpdateDownloadProgress p) {
    if (mounted) setState(() => _prog = p);
  }

  void _startDownload() =>
      UpdateService.instance.downloadUpdate(widget.result);

  void _installNow() {
    final path = _prog.localPath;
    if (path != null) UpdateService.instance.launchInstaller(path);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _prog.state == UpdateDownloadState.readyToInstall
                      ? Icons.check_circle_outline
                      : Icons.system_update_alt_rounded,
                  size: 16,
                  color: _prog.state == UpdateDownloadState.readyToInstall
                      ? _kGreen
                      : _kAccent,
                ),
                const SizedBox(width: 8),
                Expanded(child: _buildLabel()),
                const SizedBox(width: 8),
                _buildAction(),
                // Dismiss — hidden while downloading
                if (_prog.state != UpdateDownloadState.downloading)
                  GestureDetector(
                    onTap: () {
                      UpdateService.instance.resetDownload();
                      widget.onDismiss();
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.close, size: 16, color: _kText),
                    ),
                  ),
              ],
            ),
          ),
          // Progress bar — only shown while downloading
          if (_prog.state == UpdateDownloadState.downloading)
            LinearProgressIndicator(
              value: _prog.total > 0 ? _prog.fraction : null,
              backgroundColor: _kBg,
              color: _kAccent,
              minHeight: 2,
            ),
        ],
      ),
    );
  }

  Widget _buildLabel() {
    switch (_prog.state) {
      case UpdateDownloadState.idle:
        return Text(
          'Update available: ${widget.result.latestTag}',
          style: const TextStyle(color: _kText, fontSize: 12,
              fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        );
      case UpdateDownloadState.downloading:
        final pct = _prog.total > 0
            ? ' ${(_prog.fraction * 100).toStringAsFixed(0)}%'
            : '';
        return Text(
          'Downloading$pct…',
          style: const TextStyle(color: _kText, fontSize: 12,
              fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        );
      case UpdateDownloadState.readyToInstall:
        return const Text(
          'Ready to install — app will restart',
          style: TextStyle(color: _kGreen, fontSize: 12,
              fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        );
      case UpdateDownloadState.error:
        return Text(
          'Download failed: ${_prog.errorMessage ?? 'unknown error'}',
          style: const TextStyle(color: _kRed, fontSize: 12,
              fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  Widget _buildAction() {
    final btnStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    switch (_prog.state) {
      case UpdateDownloadState.idle:
        return TextButton(
          onPressed: _startDownload,
          style: btnStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(_kAccent)),
          child: const Text('Download & Install',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        );
      case UpdateDownloadState.downloading:
        return const SizedBox.shrink();
      case UpdateDownloadState.readyToInstall:
        return TextButton(
          onPressed: _installNow,
          style: btnStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(_kGreen)),
          child: const Text('Install Now & Quit',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        );
      case UpdateDownloadState.error:
        return TextButton(
          onPressed: _startDownload,
          style: btnStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(_kAccent)),
          child: const Text('Retry',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Full-width title-bar fringe — rendered at top of every screen on desktop
// ---------------------------------------------------------------------------

class _AppTitleBar extends StatelessWidget {
  const _AppTitleBar({required this.isMac});
  final bool isMac;

  static const _kBg = Color(0xFF0F172A);

  @override
  Widget build(BuildContext context) {
    if (isMac) {
      return DragToMoveArea(
        child: Container(height: 28, color: _kBg),
      );
    }
    return DragToMoveArea(
      child: Container(
        height: 36,
        color: _kBg,
        child: const Row(
          children: [Spacer(), _WinTitleControls()],
        ),
      ),
    );
  }
}

class _WinTitleControls extends StatelessWidget {
  const _WinTitleControls();

  @override
  Widget build(BuildContext context) {
    const iconColor = Color(0xFF94A3B8);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WCtrlBtn(icon: Icons.remove,      color: iconColor,         onTap: () => windowManager.minimize()),
        _WCtrlBtn(icon: Icons.crop_square, color: iconColor,         onTap: () async {
          if (await windowManager.isMaximized()) { windowManager.unmaximize(); } else { windowManager.maximize(); }
        }),
        _WCtrlBtn(icon: Icons.close,       color: Colors.redAccent,  onTap: () => windowManager.close()),
      ],
    );
  }
}

class _WCtrlBtn extends StatefulWidget {
  const _WCtrlBtn({required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  State<_WCtrlBtn> createState() => _WCtrlBtnState();
}

class _WCtrlBtnState extends State<_WCtrlBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: _hovered ? widget.color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(widget.icon, size: 14, color: widget.color),
        ),
      ),
    );
  }
}
