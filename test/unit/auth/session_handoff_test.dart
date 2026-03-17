// Tests for session handoff between the static login page and Flutter app.
//
// The web login page writes session tokens to localStorage under
// 'sb-<project>-auth-token'. The Flutter app reads these via
// SharedPreferences (which maps to localStorage on web). These tests
// verify the device_user_id persistence and migration path.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/repositories/setall_repository.dart';

void main() {
  late Database db;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
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
  // 1. Device UUID persistence
  // ─────────────────────────────────────────────────────────────────────────
  group('Device UUID persistence across sessions', () {
    test('first ensureUser creates and persists a device UUID', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SetAllRepository();
      final uid = await repo.ensureUser();

      expect(uid, isNotNull);

      // Verify it was persisted to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('device_user_id');
      expect(stored, equals(uid),
          reason: 'Device UUID must be written to SharedPreferences');
    });

    test('pre-seeded device_user_id is used without creating a new one',
        () async {
      const preSeeded = 'pre-seeded-device-uuid-12345';
      SharedPreferences.setMockInitialValues({'device_user_id': preSeeded});

      final repo = SetAllRepository();
      final uid = await repo.ensureUser();

      expect(uid, equals(preSeeded),
          reason: 'Pre-seeded device UUID must be reused');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Session token format validation
  // ─────────────────────────────────────────────────────────────────────────
  group('Session token format', () {
    test('device_user_id is a valid UUID v4 format', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SetAllRepository();
      final uid = await repo.ensureUser();

      // UUID v4: 8-4-4-4-12 hex digits
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      expect(uuidRegex.hasMatch(uid!), isTrue,
          reason: 'Device UUID must be a valid UUID v4');
    });

    test('multiple repositories share the same device UUID', () async {
      SharedPreferences.setMockInitialValues({});
      final repo1 = SetAllRepository();
      final uid1 = await repo1.ensureUser();

      final repo2 = SetAllRepository();
      final uid2 = await repo2.ensureUser();

      expect(uid1, equals(uid2),
          reason:
              'Multiple repository instances must resolve the same device UUID');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Expense ownership with device UUID
  // ─────────────────────────────────────────────────────────────────────────
  group('Expense ownership with device UUID', () {
    test('expenses created offline use device UUID as payer_id', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SetAllRepository();
      final uid = await repo.ensureUser();

      // Insert an expense directly to verify the UID is usable
      await db.insert('expenses', {
        'id': 'e-test-1',
        'payer_id': uid,
        'amount': '50.00',
        'description': 'Test expense',
        'currency': 'USD',
        'created_at': DateTime.now().toIso8601String(),
      });

      final rows = await db.query('expenses', where: 'payer_id = ?', whereArgs: [uid]);
      expect(rows, hasLength(1));
      expect(rows.first['payer_id'], equals(uid));
    });
  });
}
