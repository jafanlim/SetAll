// Tests for Riverpod auth-related providers.
//
// Verifies that [currentUserIdProvider] and [setAllRepositoryProvider]
// correctly reflect authentication state transitions without requiring
// a live Supabase connection.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:setall/core/providers/setall_providers.dart';
import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/repositories/setall_repository.dart';

void main() {
  late Database db;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalDatabase.resetForTesting();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE groups (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, creator_id TEXT NOT NULL,
              created_by TEXT, type TEXT NOT NULL DEFAULT 'normal',
              is_deleted INTEGER NOT NULL DEFAULT 0, deleted_at TEXT,
              icon_name TEXT, color_value INTEGER, avatar_url TEXT,
              default_currency TEXT,
              created_at TEXT, updated_at TEXT, synced_at INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE expenses (
              id TEXT PRIMARY KEY, group_id TEXT, payer_id TEXT NOT NULL,
              created_by TEXT, amount TEXT NOT NULL, total_amount TEXT,
              base_amount_at_entry TEXT, is_income INTEGER NOT NULL DEFAULT 0,
              description TEXT, currency TEXT, split_type TEXT, category TEXT,
              original_amount TEXT, original_currency TEXT,
              exchange_rate_applied TEXT, universal_usd_amount TEXT,
              created_at TEXT, updated_at TEXT, synced_at INTEGER,
              icon_codepoint INTEGER, icon_color INTEGER,
              attachment_urls TEXT, notes TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE splits (
              id TEXT PRIMARY KEY, expense_id TEXT NOT NULL,
              user_id TEXT NOT NULL, universal_usd_owed TEXT NOT NULL,
              entry_amount_owed TEXT, created_at TEXT, synced_at INTEGER,
              UNIQUE(expense_id, user_id)
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
            CREATE TABLE group_members (
              group_id TEXT NOT NULL, user_id TEXT NOT NULL,
              joined_at TEXT, synced_at INTEGER,
              PRIMARY KEY (group_id, user_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE left_groups (group_id TEXT PRIMARY KEY, left_at TEXT)
          ''');
          await db.execute('''
            CREATE TABLE deleted_groups_log (
              group_id TEXT PRIMARY KEY, group_name TEXT NOT NULL,
              creator_id TEXT NOT NULL, deleted_by_uid TEXT NOT NULL,
              deleted_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    LocalDatabase.injectForTesting(db);
  });

  tearDown(() async {
    await db.close();
    LocalDatabase.resetForTesting();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Unauthenticated state (no Supabase client, no device UUID)
  // ─────────────────────────────────────────────────────────────────────────
  group('Unauthenticated state', () {
    test('currentUserIdProvider returns null when no client and no device UUID',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final uid = container.read(currentUserIdProvider);
      expect(uid, isNull,
          reason: 'Without Supabase or device UUID, user should be null');
    });

    test('setAllRepositoryProvider creates a repo without Supabase client', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final repo = container.read(setAllRepositoryProvider);
      expect(repo, isA<SetAllRepository>());
      expect(repo.isConfigured, isFalse,
          reason: 'No Supabase client means repo is unconfigured');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Device-UUID fallback (offline auth)
  // ─────────────────────────────────────────────────────────────────────────
  group('Device-UUID fallback authentication', () {
    test('ensureUser returns a device UUID when no Supabase client', () async {
      final repo = SetAllRepository();
      final uid = await repo.ensureUser();
      expect(uid, isNotNull);
      expect(uid!.length, greaterThan(8),
          reason: 'Device UUID should be a valid UUID string');
    });

    test('ensureUser returns the same UUID on subsequent calls', () async {
      final repo = SetAllRepository();
      final uid1 = await repo.ensureUser();
      final uid2 = await repo.ensureUser();
      expect(uid1, equals(uid2),
          reason: 'Device UUID must be stable across calls');
    });

    test('currentUserId reflects device UUID after ensureUser', () async {
      final repo = SetAllRepository();
      await repo.ensureUser();
      expect(repo.currentUserId, isNotNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Provider dependency chain
  // ─────────────────────────────────────────────────────────────────────────
  group('Provider dependency chain', () {
    test('currencyServiceProvider resolves without Supabase', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final svc = container.read(currencyServiceProvider);
      expect(svc, isNotNull);
    });

    test('balanceServiceProvider resolves without Supabase', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final svc = container.read(balanceServiceProvider);
      expect(svc, isNotNull);
    });

    test('syncServiceProvider resolves without Supabase', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final svc = container.read(syncServiceProvider);
      expect(svc, isNotNull);
    });
  });
}
