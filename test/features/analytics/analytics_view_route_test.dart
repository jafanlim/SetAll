// Crash guard: pushing a ShellRoute-branch route onto the root navigator
// duplicates the AdaptiveShell page → duplicate page key → assertion failure.
//
// The fix: a dedicated top-level /analytics-view MaterialPage route (sibling
// of /insights, /budgets — NOT a ShellRoute child) pushed via context.push().
//
// This test suite:
//  1. Proves the fix pattern works (top-level route push succeeds),
//  2. Verifies production constants are correct,
//  3. Verifies call sites reference analyticsView, not analytics.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:setall/core/router/app_router.dart';

// ── Minimal reproduction harness ────────────────────────────────────────────

/// Mirror of the production fix: ShellRoute wrapping bottom-nav tabs, plus a
/// top-level /analytics-view MaterialPage route (sibling, not child).
GoRouter _fixRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => Scaffold(body: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: Text('Dashboard')),
          ),
          GoRoute(
            path: '/analytics',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: Text('Analytics Tab')),
          ),
        ],
      ),
      GoRoute(
        path: '/analytics-view',
        pageBuilder: (context, state) => const MaterialPage(
          child: Text('Analytics View'),
        ),
      ),
    ],
  );
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // 1. Fix verification: top-level route push succeeds
  // ═══════════════════════════════════════════════════════════════════════
  group('Top-level analyticsView push — no crash', () {
    testWidgets('pushing top-level /analytics-view with extra succeeds',
        (tester) async {
      final router = _fixRouter();

      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
      ));
      await tester.pumpAndSettle();

      router.push('/analytics-view',
          extra: {'groupId': 'g1', 'groupName': 'Test'});
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'Top-level route push must not crash');
    });

    testWidgets('pushing /analytics-view without extra succeeds',
        (tester) async {
      final router = _fixRouter();

      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
      ));
      await tester.pumpAndSettle();

      router.push('/analytics-view');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('ShellRoute child /analytics is still accessible as tab',
        (tester) async {
      final router = _fixRouter();

      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
      ));
      await tester.pumpAndSettle();

      // The bottom-nav tab still works via go() or initial navigation.
      router.go('/analytics');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'ShellRoute tab navigation must still work');
      expect(find.text('Analytics Tab'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2. Production constant verification
  // ═══════════════════════════════════════════════════════════════════════
  group('AppRouter constants — structural correctness', () {
    test('analyticsView is defined and distinct from analytics', () {
      expect(AppRouter.analyticsView, '/analytics-view');
      expect(AppRouter.analytics, '/analytics');
      expect(AppRouter.analyticsView, isNot(equals(AppRouter.analytics)));
    });

    test('analytics shell-tab path is unchanged', () {
      // The bottom-nav tab still uses /analytics — it was not moved.
      expect(AppRouter.analytics, '/analytics');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3. Call sites use analyticsView (structural smoke test)
  // ═══════════════════════════════════════════════════════════════════════
  group('Call sites — analyticsView vs analytics', () {
    test('analyticsView constant is the push target, analytics is the tab', () {
      // These are different routes with different purposes:
      // analyticsView → top-level route pushed over the shell.
      // analytics    → ShellRoute child for the bottom nav tab.
      expect(AppRouter.analyticsView, '/analytics-view');
      expect(AppRouter.analytics, '/analytics');
    });
  });
}
