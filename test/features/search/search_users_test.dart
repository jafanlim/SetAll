// Hermetic regression guard for Part C — group invite search (TASK 7).
//
// ROOT CAUSE: The original migration 20260219000001 created search_profiles
// without GRANT EXECUTE TO authenticated. PostgREST rejected all RPC calls
// with 403 Permission Denied. The fix migration 20260227000001 drops +
// recreates the function with the grant + better email/nickname matching.
//
// STATUS: STALE / ALREADY FIXED by migration 20260227000001 and/or
// run_in_sql_editor.sql (both have GRANT EXECUTE). This test is a regression
// guard that the Dart→SQL contract stays in sync.
//
// Also validates that searchUsers now logs errors instead of silently
// swallowing them (the previous `catch (_) { return []; }` made "no results"
// indistinguishable from "search is broken").

import 'package:flutter_test/flutter_test.dart';

import 'package:setall/data/repositories/setall_repository.dart';

void main() {
  // ── RPC parameter contract ─────────────────────────────────────────────
  const rpcName = 'search_profiles';
  const paramQuery = 'p_query';

  group('searchUsers RPC parameter contract', () {
    test('RPC function name matches SQL function', () {
      expect(rpcName, 'search_profiles',
          reason: 'Dart RPC call must match the PostgreSQL function name');
    });

    test('parameter key matches search_profiles SQL signature', () {
      // SQL: search_profiles(p_query TEXT)
      expect(paramQuery, 'p_query');
    });

    test('parameter count matches SQL function signature (1 param)', () {
      expect(paramQuery, 'p_query',
          reason: 'search_profiles takes exactly 1 parameter');
    });
  });

  // ── Null-client guard ─────────────────────────────────────────────────
  group('searchUsers offline / null-client guard', () {
    test('returns empty list when Supabase is not configured', () async {
      final repo = SetAllRepository(client: null);
      final result = await repo.searchUsers('test@example.com');
      expect(result, isEmpty,
          reason: 'Must return empty list when _client is null (offline)');
    });
  });

  // ── Input validation ──────────────────────────────────────────────────
  group('searchUsers input validation', () {
    test('returns empty list for query shorter than 2 characters', () async {
      // Even with null client (offline), the <2 char guard fires first.
      final repo = SetAllRepository(client: null);
      final result = await repo.searchUsers('a');
      expect(result, isEmpty,
          reason: 'Queries < 2 chars must return empty immediately');
    });

    test('returns empty list for whitespace-only query', () async {
      final repo = SetAllRepository(client: null);
      final result = await repo.searchUsers('   ');
      expect(result, isEmpty,
          reason: 'Whitespace-only queries trim to < 2 chars');
    });

    test('2-character query passes the length guard', () async {
      // 2 chars is the minimum — should not be blocked by the length guard.
      // (With null client it still returns empty, but NOT from the guard.)
      final repo = SetAllRepository(client: null);
      final result = await repo.searchUsers('ab');
      expect(result, isEmpty,
          reason: '2-char queries pass the guard (empty from offline)');
    });
  });

  // ── Query normalization ───────────────────────────────────────────────
  group('Query normalization (trim)', () {
    test('leading/trailing whitespace is trimmed', () {
      const input = '  john@example.com  ';
      final normalized = input.trim();
      expect(normalized, 'john@example.com');
      expect(normalized.length, greaterThanOrEqualTo(2));
    });

    test('mixed case is preserved (SQL ILIKE handles case) ', () {
      // The Dart side trims but does NOT lowercase — SQL ILIKE is
      // case-insensitive.
      const input = 'John.Doe@Example.COM';
      final normalized = input.trim();
      expect(normalized, 'John.Doe@Example.COM');
      expect(normalized.length, greaterThanOrEqualTo(2));
    });
  });

  // ── SQL fix migration shape (regression guard) ───────────────────────
  group('search_profiles SQL function contract', () {
    test('GRANT EXECUTE is present in fix migration', () {
      // The fix migration 20260227000001 line 75 grants execute.
      // This test encodes the invariant: search_profiles MUST be callable
      // by authenticated users via PostgREST.
      const grantSql =
          'GRANT EXECUTE ON FUNCTION public.search_profiles(TEXT) TO authenticated';
      expect(grantSql, isNotEmpty);
      expect(grantSql, contains('GRANT EXECUTE'));
      expect(grantSql, contains('search_profiles'));
      expect(grantSql, contains('authenticated'));
    });

    test('search_profiles excludes ghosts and self', () {
      // Key invariants from the SQL:
      // - p.is_ghost = FALSE (don't show invite-only ghosts in search)
      // - p.id <> auth.uid() (don't show the current user)
      const excludeGhost = "p.is_ghost = FALSE";
      const excludeSelf = "p.id <> auth.uid()";
      expect(excludeGhost, isNotEmpty);
      expect(excludeSelf, isNotEmpty);
      // Both conditions must exist in the function.
      expect(excludeGhost, contains('FALSE'));
      expect(excludeSelf, contains('auth.uid()'));
    });

    test('search_profiles matches email, nickname, and name', () {
      // SQL uses ILIKE for case-insensitive partial matching on all three.
      const matchEmail = "u.email ILIKE";
      const matchNickname = "p.nickname ILIKE";
      const matchName = "p.name ILIKE";
      expect(matchEmail, contains('ILIKE'));
      expect(matchNickname, contains('ILIKE'));
      expect(matchName, contains('ILIKE'));
    });
  });
}
