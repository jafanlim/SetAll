// ignore_for_file: lines_longer_than_80_chars
//
// Group Identity Persistence — Regression Test
// ────────────────────────────────────────────
// Verifies that group identity columns (icon_name, color_value, avatar_url,
// default_currency) survive the local DB and JSON round-trip without overflow
// or nulling.
//
// Root cause: Postgres groups.color_value was INTEGER (32-bit signed).
// ARGB colours like 0xFF14B8A6 (4,282,112,166) exceed 2^31-1 and the implicit
// cast fails, swelling the remote write, which is swallowed by catch(_){}
// leaving the server with NULL → pull-sync overwrites the local identity.
//
// Run with:
//   flutter test test/unit/group_identity_persistence_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/models/group_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/// ARGB colour that exceeds 32-bit signed integer range.
/// 0xFF14B8A6 = 4,282,112,166 > 2,147,483,647 (2^31-1)
const _highArgb = 0xFF14B8A6;

// ─────────────────────────────────────────────────────────────────────────────
// Test-DB bootstrap
// ─────────────────────────────────────────────────────────────────────────────

Future<Database> _openFreshDb() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
    );

Future<void> _createSchema(Database db, int _) async {
  await db.execute('''
    CREATE TABLE groups (
      id               TEXT PRIMARY KEY,
      name             TEXT NOT NULL,
      creator_id       TEXT NOT NULL,
      created_by       TEXT,
      type             TEXT NOT NULL DEFAULT 'normal',
      is_deleted       INTEGER NOT NULL DEFAULT 0,
      deleted_at       TEXT,
      icon_name        TEXT,
      color_value      INTEGER,
      avatar_url       TEXT,
      default_currency TEXT,
      created_at       TEXT,
      updated_at       TEXT,
      synced_at        INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE group_members (
      group_id  TEXT NOT NULL,
      user_id   TEXT NOT NULL,
      joined_at TEXT,
      synced_at INTEGER,
      PRIMARY KEY (group_id, user_id)
    )
  ''');
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

GroupModel _fromRow(Map<String, dynamic> row) => GroupModel(
      id: row['id'] as String,
      name: row['name'] as String,
      creatorId: row['creator_id'] as String,
      iconName: row['icon_name'] as String?,
      colorValue: row['color_value'] as int?,
      avatarUrl: row['avatar_url'] as String?,
      defaultCurrency: row['default_currency'] as String?,
    );

// ─────────────────────────────────────────────────────────────────────────────
// SUITE
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Database db;

  setUp(() async {
    db = await _openFreshDb();
    LocalDatabase.injectForTesting(db);
  });

  tearDown(() async {
    LocalDatabase.resetForTesting();
    await db.close();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 1. ARGB integer overflow guard
  // ─────────────────────────────────────────────────────────────────────────
  group('ARGB color_value range', () {
    test('0xFF14B8A6 exceeds 32-bit signed int range', () {
      expect(_highArgb, greaterThan(2147483647)); // 2^31 - 1
    });

    test('round-trips through SQLite INTEGER without truncation', () async {
      const gid = 'g-argb-1';
      final now = DateTime.now().toIso8601String();
      await db.insert('groups', {
        'id': gid,
        'name': 'Test Group',
        'creator_id': 'uid-1',
        'type': 'normal',
        'color_value': _highArgb,
        'icon_name': 'flight_outlined',
        'default_currency': 'EUR',
        'created_at': now,
        'updated_at': now,
      });
      final rows = await db.query('groups', where: 'id = ?', whereArgs: [gid]);
      expect(rows, hasLength(1));
      final row = rows.first;
      expect(row['color_value'], equals(_highArgb));
      expect(row['icon_name'], equals('flight_outlined'));
      expect(row['default_currency'], equals('EUR'));
    });

    test('round-trips through GroupModel.fromJson → toJson', () {
      const json = <String, dynamic>{
        'id': 'g-json-1',
        'name': 'JSON Group',
        'creator_id': 'uid-2',
        'type': 'normal',
        'icon_name': 'home_outlined',
        'color_value': _highArgb,
        'avatar_url': 'group-avatars/abc.jpg',
        'default_currency': 'GEL',
      };
      final model = GroupModel.fromJson(json);
      expect(model.colorValue, equals(_highArgb));
      expect(model.iconName, equals('home_outlined'));
      expect(model.defaultCurrency, equals('GEL'));
      expect(model.avatarUrl, equals('group-avatars/abc.jpg'));

      final back = model.toJson();
      expect(back['color_value'], equals(_highArgb));
      expect(back['icon_name'], equals('home_outlined'));
      expect(back['default_currency'], equals('GEL'));
      expect(back['avatar_url'], equals('group-avatars/abc.jpg'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Full identity round-trip (local DB)
  // ─────────────────────────────────────────────────────────────────────────
  group('Full identity round-trip', () {
    test('all identity columns survive local insert → read', () async {
      const gid = 'g-full-1';
      final now = DateTime.now().toIso8601String();
      await db.insert('groups', {
        'id': gid,
        'name': 'Identity Test',
        'creator_id': 'uid-3',
        'type': 'normal',
        'icon_name': 'local_cafe_outlined',
        'color_value': _highArgb,
        'avatar_url': 'group-avatars/test.png',
        'default_currency': 'JPY',
        'created_at': now,
        'updated_at': now,
      });
      final rows = await db.query('groups', where: 'id = ?', whereArgs: [gid]);
      final g = _fromRow(rows.first);
      expect(g.iconName, equals('local_cafe_outlined'));
      expect(g.colorValue, equals(_highArgb));
      expect(g.avatarUrl, equals('group-avatars/test.png'));
      expect(g.defaultCurrency, equals('JPY'));
    });

    test('null identity columns remain null after round-trip', () async {
      const gid = 'g-null-1';
      final now = DateTime.now().toIso8601String();
      await db.insert('groups', {
        'id': gid,
        'name': 'No Identity',
        'creator_id': 'uid-4',
        'type': 'normal',
        'created_at': now,
        'updated_at': now,
      });
      final rows = await db.query('groups', where: 'id = ?', whereArgs: [gid]);
      final g = _fromRow(rows.first);
      expect(g.iconName, isNull);
      expect(g.colorValue, isNull);
      expect(g.avatarUrl, isNull);
      expect(g.defaultCurrency, isNull);
    });

    test('partial identity survives (only icon+colour, no avatar)', () async {
      const gid = 'g-partial-1';
      final now = DateTime.now().toIso8601String();
      await db.insert('groups', {
        'id': gid,
        'name': 'Partial Identity',
        'creator_id': 'uid-5',
        'type': 'normal',
        'icon_name': 'group_outlined',
        'color_value': 0xFFBB86FC,
        'created_at': now,
        'updated_at': now,
      });
      final rows = await db.query('groups', where: 'id = ?', whereArgs: [gid]);
      final g = _fromRow(rows.first);
      expect(g.iconName, equals('group_outlined'));
      expect(g.colorValue, equals(0xFFBB86FC));
      expect(g.avatarUrl, isNull);
      expect(g.defaultCurrency, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. JSON round-trip edge cases
  // ─────────────────────────────────────────────────────────────────────────
  group('GroupModel JSON edge cases', () {
    test('color_value 0 is preserved (not treated as null)', () {
      // 0x00000000 = fully transparent black — a valid ARGB value
      const json = <String, dynamic>{
        'id': 'g-zero-1',
        'name': 'Zero Color',
        'creator_id': 'uid-6',
        'color_value': 0,
        'icon_name': 'circle_outlined',
      };
      final model = GroupModel.fromJson(json);
      expect(model.colorValue, equals(0));
      expect(model.colorValue, isNotNull);

      final back = model.toJson();
      expect(back['color_value'], equals(0));
    });

    test('toJson omits null fields (does not emit null icon/colour/avatar/currency)', () {
      const model = GroupModel(
        id: 'g-min-1',
        name: 'Minimal',
        creatorId: 'uid-7',
      );
      final json = model.toJson();
      expect(json.containsKey('icon_name'), isFalse);
      expect(json.containsKey('color_value'), isFalse);
      expect(json.containsKey('avatar_url'), isFalse);
      expect(json.containsKey('default_currency'), isFalse);
    });
  });
}
