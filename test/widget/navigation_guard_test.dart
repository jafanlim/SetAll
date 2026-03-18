// Tests for the navigation guard / redirect logic in AppRouter.
//
// The GoRouter redirect at line 87 of app_router.dart enforces:
//   - Unauthenticated users are sent to /login from any protected route.
//   - Public routes (/download, /privacy, /terms) are accessible without auth.
//   - Authenticated users on /login are redirected to / (dashboard).
//
// Since GoRouter.redirect depends on Supabase.instance.client.auth.currentUser,
// we test the redirect decision logic in isolation (same boolean conditions).

import 'package:flutter_test/flutter_test.dart';

/// Mirrors the redirect decision tree from AppRouter.create() lines 75-121.
/// Extracted so we can unit-test without a live Supabase client.
String? simulateRedirect({
  required bool isAuthenticated,
  required String location,
  bool registrationComplete = true,
  bool biometricEnabled = false,
  bool sessionUnlocked = true,
}) {
  const login = '/login';
  const register = '/register';
  const biometricGate = '/biometric-gate';
  const dashboard = '/';
  const download = '/download';
  const privacy = '/privacy';
  const terms = '/terms';

  final isLogin = location == login;
  final isRegister = location == register;
  final isBiometricGate = location == biometricGate;
  final isPublic = location == download || location == privacy || location == terms;

  // Legacy /dashboard redirect
  if (location == '/dashboard') {
    if (!isAuthenticated) return login;
    return dashboard;
  }

  // Auth guard: unauthenticated + not on login/register/public → redirect to login
  if (!isAuthenticated && !isLogin && !isRegister && !isPublic) return login;

  // Authenticated on login → redirect to dashboard (or biometric gate)
  if (isAuthenticated && isLogin) {
    if (!registrationComplete) return login; // signed out + back to login
    if (biometricEnabled) return biometricGate;
    return dashboard;
  }

  // Authenticated on biometric gate → stay
  if (isAuthenticated && isBiometricGate) return null;

  // Authenticated + biometric not unlocked → gate
  if (isAuthenticated && !sessionUnlocked && biometricEnabled) {
    return biometricGate;
  }

  return null; // no redirect needed
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // 1. Unauthenticated → /login redirects
  // ─────────────────────────────────────────────────────────────────────────
  group('Unauthenticated redirect to /login', () {
    test('/ (dashboard) redirects to /login', () {
      // Note: '/' is not login, register, or public → guard catches it
      final result = simulateRedirect(isAuthenticated: false, location: '/');
      expect(result, equals('/login'));
    });

    test('/activity redirects to /login', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/activity');
      expect(result, equals('/login'));
    });

    test('/analytics redirects to /login', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/analytics');
      expect(result, equals('/login'));
    });

    test('/wallet redirects to /login', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/wallet');
      expect(result, equals('/login'));
    });

    test('/settings redirects to /login', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/settings');
      expect(result, equals('/login'));
    });

    test('/groups redirects to /login', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/groups');
      expect(result, equals('/login'));
    });

    test('/group/abc redirects to /login', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/group/abc');
      expect(result, equals('/login'));
    });

    test('/dashboard (legacy) redirects to /login', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/dashboard');
      expect(result, equals('/login'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Public routes accessible without auth
  // ─────────────────────────────────────────────────────────────────────────
  group('Public routes (no auth required)', () {
    test('/download is accessible without auth', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/download');
      expect(result, isNull, reason: '/download is a public route');
    });

    test('/privacy is accessible without auth', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/privacy');
      expect(result, isNull, reason: '/privacy is a public route');
    });

    test('/terms is accessible without auth', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/terms');
      expect(result, isNull, reason: '/terms is a public route');
    });

    test('/login stays on /login when unauthenticated', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/login');
      expect(result, isNull, reason: '/login must be accessible');
    });

    test('/register stays on /register when unauthenticated', () {
      final result = simulateRedirect(isAuthenticated: false, location: '/register');
      expect(result, isNull, reason: '/register must be accessible');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Authenticated redirects
  // ─────────────────────────────────────────────────────────────────────────
  group('Authenticated user redirects', () {
    test('/login → / (dashboard) when authenticated', () {
      final result = simulateRedirect(isAuthenticated: true, location: '/login');
      expect(result, equals('/'));
    });

    test('/login → /biometric-gate when biometric enabled', () {
      final result = simulateRedirect(
        isAuthenticated: true,
        location: '/login',
        biometricEnabled: true,
      );
      expect(result, equals('/biometric-gate'));
    });

    test('/dashboard (legacy) → / when authenticated', () {
      final result = simulateRedirect(isAuthenticated: true, location: '/dashboard');
      expect(result, equals('/'));
    });

    test('authenticated user stays on /biometric-gate', () {
      final result = simulateRedirect(
        isAuthenticated: true,
        location: '/biometric-gate',
      );
      expect(result, isNull);
    });

    test('authenticated user on /activity — no redirect', () {
      final result = simulateRedirect(isAuthenticated: true, location: '/activity');
      expect(result, isNull, reason: 'Authenticated users can access /activity');
    });

    test('authenticated user on /wallet — no redirect', () {
      final result = simulateRedirect(isAuthenticated: true, location: '/wallet');
      expect(result, isNull, reason: 'Authenticated users can access /wallet');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. Biometric gate enforcement
  // ─────────────────────────────────────────────────────────────────────────
  group('Biometric gate enforcement', () {
    test('biometric enabled + not unlocked → /biometric-gate', () {
      final result = simulateRedirect(
        isAuthenticated: true,
        location: '/activity',
        biometricEnabled: true,
        sessionUnlocked: false,
      );
      expect(result, equals('/biometric-gate'));
    });

    test('biometric enabled + already unlocked → no redirect', () {
      final result = simulateRedirect(
        isAuthenticated: true,
        location: '/activity',
        biometricEnabled: true,
        sessionUnlocked: true,
      );
      expect(result, isNull);
    });
  });
}
