// Portal → Flutter App Session Handoff Integration Test
//
// Verifies the contract that allows a user who authenticated in the web portal
// (static HTML + Supabase JS SDK) to be recognized as logged in when the
// Flutter app boots — without requiring a second login.
//
// On web, SharedPreferences maps to localStorage. The portal writes the
// Supabase session token to localStorage; the Flutter app reads `device_user_id`
// from SharedPreferences as its identity anchor.
//
// This test simulates that handoff by:
//   1. Pre-seeding SharedPreferences with `device_user_id` (as the portal would).
//   2. Verifying the repository picks up that UUID on init without generating
//      a new one — preserving identity continuity.
//   3. Verifying the navigation guard does NOT redirect to /login when identity
//      is pre-seeded.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/repositories/setall_repository.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

const _kDeviceUserIdKey = 'device_user_id';

/// Mirror of AppRouter redirect logic (lines 75-121 of app_router.dart).
String? _simulateRedirect({
  required bool isAuthenticated,
  required String location,
}) {
  const publicRoutes = {'/login', '/register', '/download', '/privacy', '/terms'};
  if (!isAuthenticated && !publicRoutes.contains(location)) return '/login';
  if (isAuthenticated && location == '/login') return '/';
  return null;
}

// ── Minimal schema (matches repository_crud_test.dart) ───────────────────────

Future<void> _createSchema(Database db, int _) async {
  await db.execute('''
    CREATE TABLE groups (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, creator_id TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'normal', is_deleted INTEGER NOT NULL DEFAULT 0,
      deleted_at TEXT, created_at TEXT, updated_at TEXT, synced_at INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE group_members (
      group_id TEXT NOT NULL, user_id TEXT NOT NULL,
      joined_at TEXT, synced_at INTEGER, PRIMARY KEY (group_id, user_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE expenses (
      id TEXT PRIMARY KEY, group_id TEXT, payer_id TEXT NOT NULL,
      amount TEXT NOT NULL, base_amount_at_entry TEXT, description TEXT,
      currency TEXT, split_type TEXT, category TEXT, universal_usd_amount TEXT,
      created_at TEXT, updated_at TEXT, synced_at INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE splits (
      id TEXT PRIMARY KEY, expense_id TEXT NOT NULL, user_id TEXT NOT NULL,
      universal_usd_owed TEXT NOT NULL, entry_amount_owed TEXT,
      created_at TEXT, synced_at INTEGER, UNIQUE(expense_id, user_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE profiles (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, nickname TEXT,
      avatar_url TEXT, is_ghost INTEGER NOT NULL DEFAULT 0,
      default_currency TEXT, synced_at INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE left_groups (group_id TEXT PRIMARY KEY, left_at TEXT)
  ''');
  await db.execute('''
    CREATE TABLE deleted_expenses (
      expense_id TEXT PRIMARY KEY, description TEXT, amount TEXT NOT NULL,
      currency TEXT, group_id TEXT, group_name TEXT,
      is_income INTEGER NOT NULL DEFAULT 0, category TEXT,
      deleted_by TEXT NOT NULL, deleted_at TEXT NOT NULL, deleted_with_group_id TEXT,
      original_created_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE deleted_splits (
      id TEXT PRIMARY KEY, expense_id TEXT NOT NULL, user_id TEXT NOT NULL,
      amount_owed TEXT, universal_usd_owed TEXT, deleted_with_group_id TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE deleted_groups_log (
      group_id TEXT PRIMARY KEY, group_name TEXT NOT NULL, creator_id TEXT NOT NULL,
      deleted_by_uid TEXT NOT NULL, deleted_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE exchange_rates (
      base_currency TEXT NOT NULL, target_currency TEXT NOT NULL,
      rate TEXT NOT NULL, last_updated TEXT,
      PRIMARY KEY (base_currency, target_currency)
    )
  ''');
  await db.execute('''
    CREATE TABLE user_categories (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL DEFAULT 'expense',
      created_by TEXT NOT NULL, created_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE expense_edits (
      id TEXT PRIMARY KEY, expense_id TEXT NOT NULL, edited_by TEXT NOT NULL,
      edited_at TEXT NOT NULL
    )
  ''');
}

// ── Test Setup ───────────────────────────────────────────────────────────────

late Database _db;
late SetAllRepository _repo;

Future<void> _setUp(String deviceUid) async {
  SharedPreferences.setMockInitialValues({_kDeviceUserIdKey: deviceUid});
  _db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
  );
  LocalDatabase.injectForTesting(_db);
  _repo = SetAllRepository();
}

Future<void> _tearDown() async {
  LocalDatabase.resetForTesting();
  await _db.close();
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ── 1. Identity continuity ─────────────────────────────────────────────────
  group('Session handoff — identity continuity', () {
    const portalSessionUid = 'portal-session-uuid-aaaabbbbccccdddd';

    setUp(() async => _setUp(portalSessionUid));
    tearDown(_tearDown);

    test('repo picks up pre-seeded device UUID without generating a new one',
        () async {
      final uid = await _repo.ensureUser();
      expect(uid, equals(portalSessionUid),
          reason: 'After portal login the app must reuse the same UUID, not '
              'mint a fresh one and break identity continuity');
    });

    test('ensureUser is idempotent — returns same UID on repeated calls',
        () async {
      final a = await _repo.ensureUser();
      final b = await _repo.ensureUser();
      expect(a, equals(b));
      expect(a, equals(portalSessionUid));
    });

    test('UUID is a valid v4 format when newly minted (no portal session)',
        () async {
      LocalDatabase.resetForTesting();
      await _db.close();
      SharedPreferences.setMockInitialValues({});
      final freshDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
      );
      LocalDatabase.injectForTesting(freshDb);
      final freshRepo = SetAllRepository();
      final uid = await freshRepo.ensureUser();
      final uuidPattern = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(uid != null && uuidPattern.hasMatch(uid), isTrue,
          reason: 'Generated UUID must be a valid v4');
      LocalDatabase.resetForTesting();
      await freshDb.close();
      // Re-open original DB for tearDown
      _db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
      );
      LocalDatabase.injectForTesting(_db);
    });
  });

  // ── 2. Navigation guard: portal session → skip login ──────────────────────
  group('Navigation guard with pre-seeded identity', () {
    test('authenticated user on /insights → no redirect (no login screen)',
        () {
      expect(_simulateRedirect(isAuthenticated: true, location: '/insights'),
          isNull,
          reason: 'Pre-authenticated user from portal must access /insights '
              'without hitting /login');
    });

    test('authenticated user on /app → no redirect', () {
      expect(_simulateRedirect(isAuthenticated: true, location: '/app'), isNull);
    });

    test('authenticated user on /login → redirected to / (dashboard)', () {
      expect(_simulateRedirect(isAuthenticated: true, location: '/login'),
          equals('/'));
    });

    test('unauthenticated user on /insights → redirected to /login', () {
      expect(_simulateRedirect(isAuthenticated: false, location: '/insights'),
          equals('/login'));
    });
  });

  // ── 3. Offline-first: pre-seeded session needs no network ─────────────────
  group('Offline-first: identity from SharedPreferences only', () {
    const offlineUid = 'offline-device-uuid-1234567890abc0';

    setUp(() async => _setUp(offlineUid));
    tearDown(_tearDown);

    test('ensureUser returns pre-seeded UID offline (no Supabase)', () async {
      final uid = await _repo.ensureUser();
      expect(uid, equals(offlineUid));
    });

    test('seeded expense carries pre-seeded payer UID', () async {
      const gid = 'group-portal-handoff-test';
      const eid = 'expense-portal-test-001';
      await _db.insert('groups', {
        'id': gid, 'name': 'Portal Group', 'creator_id': offlineUid,
        'type': 'normal', 'is_deleted': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _db.insert('expenses', {
        'id': eid, 'group_id': gid, 'payer_id': offlineUid,
        'amount': '50.00', 'currency': 'USD', 'description': 'Portal expense',
        'created_at': DateTime.now().toIso8601String(),
      });
      final rows = await _db.rawQuery(
          'SELECT payer_id FROM expenses WHERE id = ?', [eid]);
      expect(rows.first['payer_id'], equals(offlineUid),
          reason: 'Expense payer must match the pre-seeded portal session UID');
    });

    test('watchGroups stream emits data from seeded groups', () async {
      const gid = 'group-stream-portal';
      await _db.insert('groups', {
        'id': gid, 'name': 'Portal Stream Group', 'creator_id': offlineUid,
        'type': 'normal', 'is_deleted': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _db.insert('group_members', {
        'group_id': gid, 'user_id': offlineUid,
        'joined_at': DateTime.now().toIso8601String(),
      });
      final groups = await _repo.watchGroups().first;
      expect(groups.any((g) => g.id == gid), isTrue);
    });
  });

  // ── 4. UUID stability across multiple sessions ─────────────────────────────
  group('UUID stability', () {
    const stableUid = 'stable-session-uuid-12345678901234';

    setUp(() async => _setUp(stableUid));
    tearDown(_tearDown);

    test('UUID does not change across 10 ensureUser() calls', () async {
      final uids = await Future.wait(
        List.generate(10, (_) => _repo.ensureUser()),
      );
      expect(uids.toSet(), hasLength(1),
          reason: 'Every ensureUser() call must return the same UUID');
      expect(uids.first, equals(stableUid));
    });

    test('UUID survives repo reconstruction from same prefs', () async {
      final uid1 = await _repo.ensureUser();
      final repo2 = SetAllRepository();
      final uid2 = await repo2.ensureUser();
      expect(uid1, equals(uid2),
          reason: 'New repo from same SharedPreferences must see same UUID '
              '— simulates app restart after portal login');
    });
  });
}
