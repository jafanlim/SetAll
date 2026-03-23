// Wallet entry model + business logic + soft delete + totals + sync tests.
//
// Covers Groups 1-6 — all pure Dart, no DB setup required.
// sqflite_common_ffi IS available but the static LocalDatabase singleton
// cannot be injected for unit tests; Group 7 (DB integration) is therefore
// omitted per the spec's NOTE ON DB TESTS.

import 'package:flutter_test/flutter_test.dart';
import 'package:setall/data/models/wallet_entry_model.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 1 — WalletEntryModel: serialisation
  // ──────────────────────────────────────────────────────────────────────────
  group('WalletEntryModel: serialisation', () {
    test('fromJson creates model with all fields', () {
      final now = DateTime.now().toIso8601String();
      final map = <String, dynamic>{
        'id': 'test-id-1',
        'user_id': 'user-123',
        'amount': 42.50,
        'is_income': true,
        'description': 'Salary',
        'category': 'Income',
        'currency': 'USD',
        'original_amount': null,
        'original_currency': null,
        'exchange_rate_applied': null,
        'universal_usd_amount': '42.50',
        'icon_codepoint': null,
        'icon_color': null,
        'notes': null,
        'attachment_urls': null,
        'deleted_at': null,
        'created_at': now,
        'updated_at': now,
        'synced_at': null,
      };
      final entry = WalletEntryModel.fromJson(map);
      expect(entry.id, 'test-id-1');
      expect(entry.userId, 'user-123');
      expect(entry.isIncome, true);
      expect(entry.description, 'Salary');
      expect(entry.universalUsdAmount, '42.50');
      expect(entry.deletedAt, isNull);
    });

    test('toJson round-trips all fields', () {
      final now = DateTime(2026, 3, 1).toIso8601String();
      final entry = WalletEntryModel(
        id: 'abc',
        userId: 'u1',
        amount: '10.00',
        isIncome: false,
        description: 'Coffee',
        category: 'Food',
        currency: 'GEL',
        universalUsdAmount: '3.70',
        createdAt: now,
        updatedAt: now,
      );
      final map = entry.toJson();
      expect(map['id'], 'abc');
      expect(map['is_income'], 0); // toJson stores bool as int
      expect(map['currency'], 'GEL');
      expect(map['universal_usd_amount'], '3.70');
      expect(map['deleted_at'], isNull);
    });

    test('copyWith preserves unchanged fields', () {
      final now = DateTime(2026, 1, 1).toIso8601String();
      final original = WalletEntryModel(
        id: 'x',
        userId: 'u',
        amount: '5.00',
        isIncome: true,
        description: 'Test',
        category: 'Other',
        currency: 'USD',
        universalUsdAmount: '5.00',
        createdAt: now,
        updatedAt: now,
      );
      final copy = original.copyWith(description: 'Updated');
      expect(copy.description, 'Updated');
      expect(copy.id, 'x');
      expect(copy.isIncome, true);
      expect(copy.universalUsdAmount, '5.00');
    });

    test('fromJson handles null optional fields gracefully', () {
      final now = DateTime.now().toIso8601String();
      final map = <String, dynamic>{
        'id': 'min',
        'user_id': 'u',
        'amount': 1.0,
        'is_income': false,
        'description': '',
        'category': 'Other',
        'currency': 'USD',
        'universal_usd_amount': '1.0',
        'created_at': now,
        'updated_at': now,
      };
      expect(() => WalletEntryModel.fromJson(map), returnsNormally);
      final entry = WalletEntryModel.fromJson(map);
      expect(entry.deletedAt, isNull);
      expect(entry.syncedAt, isNull);
      expect(entry.notes, isNull);
    });

    test('deleted entry has non-null deletedAt', () {
      final now = DateTime.now().toIso8601String();
      final map = <String, dynamic>{
        'id': 'd1',
        'user_id': 'u',
        'amount': 1.0,
        'is_income': false,
        'description': 'Deleted item',
        'category': 'Other',
        'currency': 'USD',
        'universal_usd_amount': '1.0',
        'deleted_at': now,
        'created_at': now,
        'updated_at': now,
      };
      final entry = WalletEntryModel.fromJson(map);
      expect(entry.deletedAt, isNotNull);
    });

    test('fromJson parses is_income as int (SQLite stores bools as int)', () {
      final now = DateTime.now().toIso8601String();
      final mapWithInt = <String, dynamic>{
        'id': 'int-bool',
        'user_id': 'u',
        'amount': 5.0,
        'is_income': 1, // SQLite integer true
        'description': '',
        'category': 'Other',
        'currency': 'USD',
        'universal_usd_amount': '5.0',
        'created_at': now,
        'updated_at': now,
      };
      final entry = WalletEntryModel.fromJson(mapWithInt);
      expect(entry.isIncome, isTrue);
    });

    test('fromJson parses is_income as bool (Supabase returns native bool)', () {
      final now = DateTime.now().toIso8601String();
      final mapWithBool = <String, dynamic>{
        'id': 'bool-bool',
        'user_id': 'u',
        'amount': 5.0,
        'is_income': false,
        'description': '',
        'category': 'Other',
        'currency': 'USD',
        'universal_usd_amount': '5.0',
        'created_at': now,
        'updated_at': now,
      };
      final entry = WalletEntryModel.fromJson(mapWithBool);
      expect(entry.isIncome, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 2 — WalletEntryModel: business logic
  // ──────────────────────────────────────────────────────────────────────────
  group('WalletEntryModel: business logic', () {
    test('isDeleted is true when deletedAt is set', () {
      final now = DateTime.now().toIso8601String();
      final entry = WalletEntryModel(
        id: 'x',
        userId: 'u',
        amount: '1.00',
        isIncome: false,
        description: '',
        category: 'Other',
        currency: 'USD',
        universalUsdAmount: '1.00',
        createdAt: now,
        updatedAt: now,
        deletedAt: now,
      );
      expect(entry.deletedAt, isNotNull);
    });

    test('income entry has positive universalUsdAmount', () {
      final entry = _makeEntry(amount: '500.00', isIncome: true, usd: '500.00');
      final usd = double.tryParse(entry.universalUsdAmount) ?? 0;
      expect(usd, greaterThan(0));
      expect(entry.isIncome, isTrue);
    });

    test('expense entry has positive amount (stored as absolute)', () {
      final entry = _makeEntry(amount: '12.50', isIncome: false, usd: '12.50');
      final amount = double.tryParse(entry.amount) ?? 0;
      expect(amount, greaterThan(0));
      expect(entry.isIncome, isFalse);
    });

    test('pending entry has null syncedAt', () {
      final entry = _makeEntry(amount: '1.00', isIncome: false, usd: '1.00');
      expect(entry.syncedAt, isNull);
    });

    test('synced entry has non-null syncedAt', () {
      final syncedAt = DateTime.now().millisecondsSinceEpoch;
      final now = DateTime.now().toIso8601String();
      final entry = WalletEntryModel(
        id: 's1',
        userId: 'u',
        amount: '1.00',
        isIncome: false,
        description: 'Synced',
        category: 'Other',
        currency: 'USD',
        universalUsdAmount: '1.00',
        createdAt: now,
        updatedAt: now,
        syncedAt: syncedAt,
      );
      expect(entry.syncedAt, isNotNull);
      expect(entry.syncedAt, syncedAt);
    });

    test('default currency is USD', () {
      final entry = WalletEntryModel(
        id: 'def', userId: 'u', amount: '1.00',
      );
      expect(entry.currency, 'USD');
    });

    test('default category is Other', () {
      final entry = WalletEntryModel(
        id: 'def', userId: 'u', amount: '1.00',
      );
      expect(entry.category, 'Other');
    });

    test('default isIncome is false', () {
      final entry = WalletEntryModel(
        id: 'def', userId: 'u', amount: '1.00',
      );
      expect(entry.isIncome, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 3 — WalletEntryModel: toSupabaseJson
  // ──────────────────────────────────────────────────────────────────────────
  group('WalletEntryModel: toSupabaseJson', () {
    test('toSupabaseJson uses snake_case keys', () {
      final now = DateTime.now().toIso8601String();
      final entry = WalletEntryModel(
        id: 'sb1',
        userId: 'u',
        amount: '20.00',
        isIncome: true,
        description: 'Test',
        category: 'Other',
        currency: 'USD',
        universalUsdAmount: '20.00',
        createdAt: now,
        updatedAt: now,
      );
      final json = entry.toSupabaseJson();
      expect(json.containsKey('user_id'), isTrue);
      expect(json.containsKey('is_income'), isTrue);
      expect(json.containsKey('universal_usd_amount'), isTrue);
      expect(json.containsKey('userId'), isFalse);
      expect(json.containsKey('isIncome'), isFalse);
    });

    test('toSupabaseJson stores is_income as bool (not int)', () {
      final now = DateTime.now().toIso8601String();
      final entry = WalletEntryModel(
        id: 'sb2', userId: 'u', amount: '5.00', isIncome: true,
        description: '', category: 'Other', currency: 'USD',
        universalUsdAmount: '5.00', createdAt: now, updatedAt: now,
      );
      final json = entry.toSupabaseJson();
      expect(json['is_income'], isA<bool>());
      expect(json['is_income'], isTrue);
    });

    test('toSupabaseJson stores amount as double', () {
      final now = DateTime.now().toIso8601String();
      final entry = WalletEntryModel(
        id: 'sb3', userId: 'u', amount: '99.99', isIncome: false,
        description: '', category: 'Other', currency: 'USD',
        universalUsdAmount: '99.99', createdAt: now, updatedAt: now,
      );
      final json = entry.toSupabaseJson();
      expect(json['amount'], isA<double>());
      expect(json['amount'], closeTo(99.99, 0.001));
    });

    test('toSupabaseJson omits null optional fields', () {
      final now = DateTime.now().toIso8601String();
      final entry = WalletEntryModel(
        id: 'sb4', userId: 'u', amount: '1.00', isIncome: false,
        description: '', category: 'Other', currency: 'USD',
        universalUsdAmount: '1.00', createdAt: now, updatedAt: now,
      );
      final json = entry.toSupabaseJson();
      expect(json.containsKey('original_amount'), isFalse);
      expect(json.containsKey('original_currency'), isFalse);
      expect(json.containsKey('notes'), isFalse);
      expect(json.containsKey('deleted_at'), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 4 — Totals calculation logic
  // ──────────────────────────────────────────────────────────────────────────
  group('Totals calculation logic', () {
    test('net worth = income - expenses', () {
      final entries = [
        _makeEntry(amount: '1000.00', isIncome: true,  usd: '1000.00'),
        _makeEntry(amount: '200.00',  isIncome: false, usd: '200.00'),
        _makeEntry(amount: '150.00',  isIncome: false, usd: '150.00'),
      ];
      final income = entries
          .where((e) => e.isIncome)
          .fold(0.0, (s, e) => s + (double.tryParse(e.universalUsdAmount) ?? 0));
      final expenses = entries
          .where((e) => !e.isIncome)
          .fold(0.0, (s, e) => s + (double.tryParse(e.universalUsdAmount) ?? 0));
      expect(income,   1000.0);
      expect(expenses, 350.0);
      expect(income - expenses, 650.0);
    });

    test('deleted entries excluded from totals', () {
      final deletedAt = DateTime.now().toIso8601String();
      final entries = [
        _makeEntry(amount: '100.00', isIncome: true,  usd: '100.00'),
        _makeEntry(amount: '50.00',  isIncome: false, usd: '50.00',
            deletedAt: deletedAt),
      ];
      final active = entries.where((e) => e.deletedAt == null).toList();
      final income = active
          .where((e) => e.isIncome)
          .fold(0.0, (s, e) => s + (double.tryParse(e.universalUsdAmount) ?? 0));
      expect(income, 100.0);
      expect(active.length, 1);
    });

    test('empty wallet has zero totals', () {
      final entries = <WalletEntryModel>[];
      final income = entries
          .where((e) => e.isIncome)
          .fold(0.0, (s, e) => s + (double.tryParse(e.universalUsdAmount) ?? 0));
      final expenses = entries
          .where((e) => !e.isIncome)
          .fold(0.0, (s, e) => s + (double.tryParse(e.universalUsdAmount) ?? 0));
      expect(income,   0.0);
      expect(expenses, 0.0);
    });

    test('multi-currency entries use universalUsdAmount not raw amount', () {
      // 270 GEL entry = 100 USD
      final entry = _makeEntry(amount: '270.00', isIncome: false, usd: '100.00');
      final usd = double.tryParse(entry.universalUsdAmount) ?? 0;
      expect(usd, 100.0);
      expect(double.tryParse(entry.amount), isNot(equals(usd)));
    });

    test('all income totals correctly across multiple entries', () {
      final entries = List.generate(5, (i) => _makeEntry(
        id: 'inc$i',
        amount: '${(i + 1) * 100}.00',
        isIncome: true,
        usd: '${(i + 1) * 100}.00',
      ));
      final total = entries
          .fold(0.0, (s, e) => s + (double.tryParse(e.universalUsdAmount) ?? 0));
      expect(total, 1500.0); // 100+200+300+400+500
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 5 — Soft delete contract
  // ──────────────────────────────────────────────────────────────────────────
  group('Soft delete contract', () {
    test('soft delete sets deletedAt, does not remove entry', () {
      final now = DateTime.now().toIso8601String();
      final entry = _makeEntry(id: 'del1', amount: '5.00', isIncome: false, usd: '5.00');
      final deleted = entry.copyWith(deletedAt: now);
      expect(deleted.deletedAt, isNotNull);
      expect(deleted.id, entry.id);
      expect(deleted.description, entry.description);
    });

    test('active filter excludes soft-deleted entries', () {
      final deletedAt = DateTime.now().toIso8601String();
      final entries = [
        _makeEntry(id: 'a1', amount: '10.00', isIncome: false, usd: '10.00'),
        _makeEntry(id: 'a2', amount: '20.00', isIncome: true,  usd: '20.00',
            deletedAt: deletedAt),
        _makeEntry(id: 'a3', amount: '30.00', isIncome: false, usd: '30.00'),
      ];
      final active = entries.where((e) => e.deletedAt == null).toList();
      expect(active.length, 2);
      expect(active.map((e) => e.id), containsAll(['a1', 'a3']));
      expect(active.map((e) => e.id), isNot(contains('a2')));
    });

    test('copyWith deletedAt does not mutate original', () {
      final now = DateTime.now().toIso8601String();
      final original = _makeEntry(id: 'orig', amount: '1.00', isIncome: false, usd: '1.00');
      final deleted = original.copyWith(deletedAt: now);
      expect(original.deletedAt, isNull);
      expect(deleted.deletedAt, isNotNull);
    });

    test('copyWith without deletedAt keeps existing null', () {
      final entry = _makeEntry(id: 'keep', amount: '1.00', isIncome: false, usd: '1.00');
      final copy = entry.copyWith(description: 'Changed');
      expect(copy.deletedAt, isNull);
    });

    test('multiple soft deletes do not compound — id unchanged', () {
      final t1 = DateTime.now().toIso8601String();
      final t2 = DateTime.now().add(const Duration(seconds: 1)).toIso8601String();
      final entry = _makeEntry(id: 'multi', amount: '1.00', isIncome: false, usd: '1.00');
      final del1 = entry.copyWith(deletedAt: t1);
      final del2 = del1.copyWith(deletedAt: t2);
      expect(del2.id, 'multi');
      expect(del2.deletedAt, t2);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 6 — Sync state
  // ──────────────────────────────────────────────────────────────────────────
  group('Sync state', () {
    test('pending entries have null syncedAt', () {
      final entries = List.generate(3, (i) => _makeEntry(
        id: 'p$i',
        amount: '${(i + 1) * 10}.00',
        isIncome: i.isEven,
        usd: '${(i + 1) * 10}.00',
      ));
      final pending = entries.where((e) => e.syncedAt == null).toList();
      expect(pending.length, 3);
    });

    test('markSynced updates syncedAt via copyWith', () {
      final syncedAt = DateTime.now().millisecondsSinceEpoch;
      final entry = _makeEntry(id: 's1', amount: '1.00', isIncome: false, usd: '1.00');
      expect(entry.syncedAt, isNull);
      final synced = entry.copyWith(syncedAt: syncedAt);
      expect(synced.syncedAt, isNotNull);
      expect(synced.syncedAt, syncedAt);
    });

    test('synced entry preserves all other fields', () {
      final syncedAt = DateTime.now().millisecondsSinceEpoch;
      final entry = _makeEntry(
        id: 'preserve', amount: '42.00', isIncome: true, usd: '42.00');
      final synced = entry.copyWith(syncedAt: syncedAt);
      expect(synced.id, entry.id);
      expect(synced.amount, entry.amount);
      expect(synced.isIncome, entry.isIncome);
      expect(synced.universalUsdAmount, entry.universalUsdAmount);
    });

    test('toJson does not include synced_at (local-only field)', () {
      final syncedAt = DateTime.now().millisecondsSinceEpoch;
      final now = DateTime.now().toIso8601String();
      final entry = WalletEntryModel(
        id: 'syn', userId: 'u', amount: '1.00', isIncome: false,
        description: '', category: 'Other', currency: 'USD',
        universalUsdAmount: '1.00',
        createdAt: now, updatedAt: now,
        syncedAt: syncedAt,
      );
      final json = entry.toJson();
      expect(json.containsKey('synced_at'), isFalse);
    });

    test('toSupabaseJson does not include synced_at', () {
      final syncedAt = DateTime.now().millisecondsSinceEpoch;
      final now = DateTime.now().toIso8601String();
      final entry = WalletEntryModel(
        id: 'syn2', userId: 'u', amount: '1.00', isIncome: false,
        description: '', category: 'Other', currency: 'USD',
        universalUsdAmount: '1.00',
        createdAt: now, updatedAt: now,
        syncedAt: syncedAt,
      );
      final json = entry.toSupabaseJson();
      expect(json.containsKey('synced_at'), isFalse);
    });

    test('mixed sync states: filter pending correctly', () {
      final syncedAt = DateTime.now().millisecondsSinceEpoch;
      final now = DateTime.now().toIso8601String();
      final entries = [
        _makeEntry(id: 'ns1', amount: '1.00', isIncome: false, usd: '1.00'),
        WalletEntryModel(
          id: 'sy1', userId: 'test-user', amount: '1.00', isIncome: false,
          description: 'Test entry', category: 'Other', currency: 'USD',
          universalUsdAmount: '1.00', createdAt: now, updatedAt: now,
          syncedAt: syncedAt,
        ),
        _makeEntry(id: 'ns2', amount: '2.00', isIncome: true, usd: '2.00'),
      ];
      final pending = entries.where((e) => e.syncedAt == null).toList();
      final synced  = entries.where((e) => e.syncedAt != null).toList();
      expect(pending.length, 2);
      expect(synced.length,  1);
      expect(synced.first.id, 'sy1');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// Helper
// ────────────────────────────────────────────────────────────────────────────

WalletEntryModel _makeEntry({
  String id = 'test-id',
  String amount = '10.00',
  bool isIncome = false,
  String usd = '10.00',
  String? deletedAt,
}) {
  final now = DateTime.now().toIso8601String();
  return WalletEntryModel(
    id: id,
    userId: 'test-user',
    amount: amount,
    isIncome: isIncome,
    description: 'Test entry',
    category: 'Other',
    currency: 'USD',
    universalUsdAmount: usd,
    createdAt: now,
    updatedAt: now,
    deletedAt: deletedAt,
  );
}
