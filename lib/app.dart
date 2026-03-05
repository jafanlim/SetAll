import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/setall_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/setall_providers.dart';
import 'core/providers/theme_mode_provider.dart';
import 'core/utils/scaling_utility.dart';
import 'data/local/local_database.dart';

class SetAllApp extends ConsumerStatefulWidget {
  const SetAllApp({super.key});

  @override
  ConsumerState<SetAllApp> createState() => _SetAllAppState();
}

class _SetAllAppState extends ConsumerState<SetAllApp> {
  StreamSubscription<AuthState>? _authSub;
  String? _lastUserId;

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

    if (state.event == AuthChangeEvent.signedIn && newUid != null) {
      final isUserSwitch = _lastUserId != null && newUid != _lastUserId;
      final isFirstLogin  = _lastUserId == null;

      if (isUserSwitch) {
        // Different account — wipe SQLite and all provider caches.
        await _wipeSQLiteCache();
        _invalidateAllProviders();
      } else if (isFirstLogin) {
        // First login this session — invalidate caches only (no SQLite wipe).
        _invalidateAllProviders();
      }
      // Token refresh / session-restore with same user: do nothing extra —
      // the StreamController and its listeners stay intact.

      _lastUserId = newUid;

      // Pull remote data now that a valid session exists.
      // Using a local capture of syncServiceProvider so we don't touch
      // ref after the widget might be disposed.
      final sync = ref.read(syncServiceProvider);
      unawaited(
        sync.performFullSync().then((_) {
          if (!mounted) return;
          ref.invalidate(balanceSummaryProvider);
          ref.invalidate(recentExpensesProvider);
        }),
      );
    }

    // On sign-out always invalidate so the login screen starts clean.
    if (state.event == AuthChangeEvent.signedOut) {
      _lastUserId = null;
      _invalidateAllProviders();
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
          builder: (_, _) {
            ScalingUtility.init(context);
            final theme = Theme.of(context);
            return Container(
              color: theme.colorScheme.surface,
              child: inner,
            );
          },
        );
      },
    );
  }
}
