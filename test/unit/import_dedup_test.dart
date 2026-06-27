// Hermetic tests for import deduplication (TASK 6a).
//
// Group 1 — importDedupSig: pure function, no I/O.
// Group 2 — IngestService.flagDuplicates + commitApproved
//   uses in-memory SQLite + stubbed CurrencyService (like wallet_import_parity_test.dart).

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:setall/core/services/currency_service.dart';
import 'package:setall/core/utils/import_dedup.dart';
import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/repositories/setall_repository.dart';
import 'package:setall/features/wallet/data/ingest_row.dart';
import 'package:setall/features/wallet/data/ingest_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Stubbed rates (same pattern as wallet_import_parity_test.dart)
// ──────────────────────────────────────────────────────────────────────────────
class _StubRates extends CurrencyService {
  _StubRates() : super();

  @override
  Future<Decimal> getRate(String from, String to) async {
    if (from == to) return Decimal.one;
    const rates = {'EUR→USD': '1.08', 'GBP→USD': '1.27', 'GEL→USD': '0.3663'};
    return Decimal.parse(rates['$from→$to'] ?? '1.0');
  }

  @override
  Future<Decimal> getRateToUsd(String from) => getRate(from, 'USD');
}

const _uid = 'test-import-dedup-user';

// ── Seed helper (called after DB is injected) ────────────────────────────────
Future<void> _seedEntry({
  required String id,
  required String amount,
  required String description,
  required String currency,
  required String createdAt,
  bool isIncome = false,
}) async {
  await LocalDatabase.db.insert('expenses', {
    'id': id,
    'payer_id': _uid,
    'amount': amount,
    'description': description,
    'currency': currency,
    'created_at': createdAt,
    'is_income': isIncome ? 1 : 0,
    'category': 'General',
  });
}

void main() {
  // ── GROUP 1 — importDedupSig equality ──────────────────────────────────────

  group('importDedupSig equality', () {
    test('same day + desc + amount-to-cents + currency match', () {
      final a = importDedupSig(
        DateTime(2026, 5, 1), 'Coffee Shop', Decimal.parse('4.50'), 'USD');
      final b = importDedupSig(
        DateTime(2026, 5, 1, 23, 59), '  Coffee Shop  ', Decimal.parse('4.5'), ' usd ');
      expect(a, b);
    });

    test('differing cents do not match', () {
      final a = importDedupSig(
        DateTime(2026, 5, 1), 'Coffee', Decimal.parse('4.50'), 'USD');
      final b = importDedupSig(
        DateTime(2026, 5, 1), 'Coffee', Decimal.parse('4.51'), 'USD');
      expect(a, isNot(b));
    });

    test('differing currency does not match', () {
      final a = importDedupSig(
        DateTime(2026, 5, 1), 'Coffee', Decimal.parse('4.00'), 'EUR');
      final b = importDedupSig(
        DateTime(2026, 5, 1), 'Coffee', Decimal.parse('4.00'), 'USD');
      expect(a, isNot(b));
    });

    test('differing day does not match', () {
      final a = importDedupSig(
        DateTime(2026, 5, 1), 'Coffee', Decimal.parse('4.00'), 'USD');
      final b = importDedupSig(
        DateTime(2026, 5, 2), 'Coffee', Decimal.parse('4.00'), 'USD');
      expect(a, isNot(b));
    });

    test('differing normalized description does not match', () {
      final a = importDedupSig(
        DateTime(2026, 5, 1), 'Coffee Shop', Decimal.parse('4.00'), 'USD');
      final b = importDedupSig(
        DateTime(2026, 5, 1), 'Coffee House', Decimal.parse('4.00'), 'USD');
      expect(a, isNot(b));
    });

    test('same local day regardless of time-of-day or UTC offset', () {
      // Local DateTime objects at different hours but same calendar day → match.
      expect(
        importDedupSig(DateTime(2026, 5, 1, 0, 1), 'Coffee', Decimal.parse('4.00'), 'USD'),
        importDedupSig(DateTime(2026, 5, 1, 23, 59), 'Coffee', Decimal.parse('4.00'), 'USD'),
      );
      // Different local day → do not match.
      expect(
        importDedupSig(DateTime(2026, 5, 1, 23, 59), 'Coffee', Decimal.parse('4.00'), 'USD'),
        isNot(importDedupSig(DateTime(2026, 5, 2, 0, 1), 'Coffee', Decimal.parse('4.00'), 'USD')),
      );
    });

    test('amount rounds to cents', () {
      // 12.3456 rounds to 12.35 (half-even), 12.3449 rounds to 12.34.
      final a = importDedupSig(
        DateTime(2026, 5, 1), 'Gas', Decimal.parse('12.3456'), 'USD');
      final b = importDedupSig(
        DateTime(2026, 5, 1), 'Gas', Decimal.parse('12.3449'), 'USD');
      expect(a, isNot(b));
    });
  });

  // ── GROUP 2 — IngestService.flagDuplicates + commitApproved ────────────────

  group('IngestService flagDuplicates + commitApproved', () {
    late Database db;
    late IngestService svc;
    late SetAllRepository repo;

    setUpAll(() => sqfliteFfiInit());

    setUp(() async {
      SharedPreferences.setMockInitialValues({'device_user_id': _uid});
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
              CREATE TABLE group_members (
                group_id TEXT NOT NULL, user_id TEXT NOT NULL,
                joined_at TEXT, synced_at INTEGER,
                PRIMARY KEY (group_id, user_id)
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
                base_currency_amount TEXT,
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
              CREATE TABLE left_groups (group_id TEXT PRIMARY KEY, left_at TEXT)
            ''');
            await db.execute('''
              CREATE TABLE user_categories (
                id TEXT PRIMARY KEY, name TEXT NOT NULL,
                type TEXT NOT NULL DEFAULT 'expense',
                created_by TEXT NOT NULL, created_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE deleted_groups_log (
                group_id TEXT PRIMARY KEY, group_name TEXT NOT NULL,
                creator_id TEXT NOT NULL, deleted_by_uid TEXT NOT NULL,
                deleted_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE deleted_expenses (
                expense_id TEXT PRIMARY KEY, description TEXT,
                amount TEXT NOT NULL, original_amount TEXT, currency TEXT,
                group_id TEXT, group_name TEXT,
                is_income INTEGER NOT NULL DEFAULT 0, category TEXT,
                deleted_by TEXT NOT NULL, deleted_by_name TEXT,
                deleted_at TEXT NOT NULL, deleted_with_group_id TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE deleted_splits (
                id TEXT PRIMARY KEY, expense_id TEXT NOT NULL,
                user_id TEXT NOT NULL, amount_owed TEXT,
                universal_usd_owed TEXT, deleted_with_group_id TEXT NOT NULL
              )
            ''');
          },
        ),
      );
      LocalDatabase.injectForTesting(db);

      await db.insert('profiles', {
        'id': _uid,
        'name': 'Test User',
        'default_currency': 'USD',
        'is_ghost': 0,
      });

      repo = SetAllRepository(currencyService: _StubRates());
      svc = IngestService(repository: repo);
    });

    tearDown(() async {
      await db.close();
      LocalDatabase.resetForTesting();
    });

    test('existing entry present → matching row flagged isDuplicate + rejected', () async {
      await _seedEntry(
        id: 'existing-1',
        amount: '45.50',
        description: 'Coffee Shop',
        currency: 'USD',
        createdAt: '2026-05-01T10:00:00.000Z',
      );

      final rows = [
        IngestRow(
          date: '2026-05-01', amount: '45.50', currency: 'USD',
          description: 'Coffee Shop', rawDescription: 'Coffee Shop',
          category: 'General', isIncome: false,
        ),
        IngestRow(
          date: '2026-05-02', amount: '12.00', currency: 'USD',
          description: 'Lunch', rawDescription: 'Lunch',
          category: 'General', isIncome: false,
        ),
      ];

      final result = await svc.flagDuplicates(rows);

      expect(result[0].isDuplicate, isTrue);
      expect(result[0].status, IngestRowStatus.rejected);
      expect(result[1].isDuplicate, isFalse);
      expect(result[1].status, IngestRowStatus.pending);
    });

    test('non-matching row stays non-duplicate', () async {
      await _seedEntry(
        id: 'existing-2', amount: '100.00', description: 'Rent',
        currency: 'USD', createdAt: '2026-05-01T10:00:00.000Z',
      );

      final rows = [
        IngestRow(date: '2026-05-01', amount: '100.00', currency: 'EUR',
          description: 'Rent', rawDescription: 'Rent', category: 'General', isIncome: false),
        IngestRow(date: '2026-05-01', amount: '99.99', currency: 'USD',
          description: 'Rent', rawDescription: 'Rent', category: 'General', isIncome: false),
        IngestRow(date: '2026-05-02', amount: '100.00', currency: 'USD',
          description: 'Rent', rawDescription: 'Rent', category: 'General', isIncome: false),
      ];

      final result = await svc.flagDuplicates(rows);
      for (final r in result) {
        expect(r.isDuplicate, isFalse);
        expect(r.status, IngestRowStatus.pending);
      }
    });

    test('commitApproved skips duplicate rows', () async {
      await _seedEntry(
        id: 'existing-3', amount: '200.00', description: 'Hotel',
        currency: 'USD', createdAt: '2026-06-01T00:00:00.000Z',
      );

      final rows = await svc.flagDuplicates([
        IngestRow(date: '2026-06-01', amount: '200.00', currency: 'USD',
          description: 'Hotel', rawDescription: 'Hotel', category: 'Travel', isIncome: false),
        IngestRow(date: '2026-06-02', amount: '50.00', currency: 'USD',
          description: 'Taxi', rawDescription: 'Taxi', category: 'Travel', isIncome: false,
          status: IngestRowStatus.approved),
      ]);

      expect(rows[0].isDuplicate, isTrue);
      expect(rows[0].status, IngestRowStatus.rejected);
      expect(rows[1].isDuplicate, isFalse);

      final committed = await svc.commitApproved(rows);
      expect(committed, 1);

      final entries = await repo.getWalletEntries();
      // 1 seed (Hotel) + 1 committed (Taxi) = 2. Duplicate Hotel NOT committed.
      expect(entries.length, 2);
      expect(entries.where((e) => e.description == 'Taxi'), hasLength(1));
    });

    test('empty rows list returns empty', () async {
      final result = await svc.flagDuplicates([]);
      expect(result, isEmpty);
    });

    test('user can override a flagged duplicate by re-approving', () async {
      // A genuine SECOND identical purchase the same day: the heuristic flags it
      // as a dup of the existing entry, but the user re-approves it on purpose.
      // isDuplicate is advisory — an approved row must still commit.
      await _seedEntry(
        id: 'existing-5', amount: '4.50', description: 'Coffee',
        currency: 'USD', createdAt: '2026-07-01T09:00:00.000Z',
      );
      final flagged = await svc.flagDuplicates([
        IngestRow(date: '2026-07-01', amount: '4.50', currency: 'USD',
          description: 'Coffee', rawDescription: 'Coffee', category: 'Food', isIncome: false),
      ]);
      expect(flagged[0].isDuplicate, isTrue);
      expect(flagged[0].status, IngestRowStatus.rejected);

      // User re-approves the badged row.
      final overridden =
          flagged.map((r) => r.copyWith(status: IngestRowStatus.approved)).toList();
      final committed = await svc.commitApproved(overridden);
      expect(committed, 1,
          reason: 'an explicitly re-approved duplicate must commit (override)');

      final entries = await repo.getWalletEntries();
      expect(entries.where((e) => e.description == 'Coffee'), hasLength(2),
          reason: 'seed + overridden second identical purchase');
    });

    test('date preservation: createdAt uses row.date', () async {
      final rows = [
        IngestRow(date: '2026-03-15', amount: '75.00', currency: 'EUR',
          description: 'Dinner', rawDescription: 'Dinner', category: 'Food',
          isIncome: false, status: IngestRowStatus.approved),
      ];

      final committed = await svc.commitApproved(rows);
      expect(committed, 1);

      final entries = await repo.getWalletEntries();
      final dinner = entries.firstWhere((e) => e.description == 'Dinner');
      expect(dinner.createdAt, '2026-03-15T00:00:00.000Z');
    });

    test('mixed: some duplicates, some new → only new committed', () async {
      await _seedEntry(
        id: 'existing-4', amount: '10.00', description: 'existing item',
        currency: 'USD', createdAt: '2026-01-15T12:00:00.000Z',
      );

      final raw = [
        IngestRow(date: '2026-01-15', amount: '10.00', currency: 'USD',
            description: 'existing item', rawDescription: 'existing item',
            category: 'General', isIncome: false),
        IngestRow(date: '2026-01-16', amount: '20.00', currency: 'USD',
            description: 'new item A', rawDescription: 'new item A',
            category: 'General', isIncome: false),
        IngestRow(date: '2026-01-17', amount: '30.00', currency: 'USD',
            description: 'new item B', rawDescription: 'new item B',
            category: 'General', isIncome: false),
      ];

      final flagged = await svc.flagDuplicates(raw);
      final toCommit = flagged.map((r) =>
          r.isDuplicate ? r : r.copyWith(status: IngestRowStatus.approved)).toList();

      final committed = await svc.commitApproved(toCommit);
      expect(committed, 2);

      final entries = await repo.getWalletEntries();
      expect(entries.length, 3); // 1 seed + 2 new
      expect(entries.any((e) => e.description == 'existing item'), isTrue);
      expect(entries.any((e) => e.description == 'new item A'), isTrue);
      expect(entries.any((e) => e.description == 'new item B'), isTrue);
    });
  });
}
