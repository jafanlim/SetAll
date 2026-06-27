// Unit tests for AnalyticsRow factories.
//
// Verifies that AnalyticsRow.fromExpense and AnalyticsRow.fromWalletEntry
// faithfully preserve amount/currency/isIncome fields — the mapping
// must never zero amounts (the web-SQLite parity guard).
//
// These are pure Dart unit tests — no ProviderContainer needed.

import 'package:flutter_test/flutter_test.dart';

import 'package:setall/data/models/expense_model.dart';
import 'package:setall/data/models/wallet_entry_model.dart';
import 'package:setall/features/analytics/presentation/screens/analytics_screen.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // AnalyticsRow.fromExpense
  // ─────────────────────────────────────────────────────────────────────────
  group('AnalyticsRow.fromExpense', () {
    test('preserves universalUsdAmount and amount', () {
      final expense = ExpenseModel(
        id: 'exp-1',
        payerId: 'user-1',
        amount: '42.50',
        universalUsdAmount: '42.50',
        currency: 'USD',
        category: 'Food',
        isIncome: false,
        description: 'Groceries',
        createdAt: '2026-06-15T12:00:00Z',
        groupId: 'g1',
      );

      final row = AnalyticsRow.fromExpense(expense);

      expect(row.universalUsdAmount, '42.50',
          reason: 'universalUsdAmount must survive the mapping');
      expect(row.amount, '42.50');
      expect(row.currency, 'USD');
      expect(row.isIncome, isFalse);
      expect(row.category, 'Food');
      expect(row.description, 'Groceries');
      expect(row.createdAt, '2026-06-15T12:00:00Z');
      expect(row.groupId, 'g1');
    });

    test('preserves income flag + original currency fields', () {
      final expense = ExpenseModel(
        id: 'exp-2',
        payerId: 'user-1',
        amount: '108.00',
        universalUsdAmount: '100.00',
        currency: 'USD',
        originalAmount: '100.00',
        originalCurrency: 'EUR',
        exchangeRateApplied: '1.08',
        category: 'Salary',
        isIncome: true,
        description: 'Freelance payment',
        createdAt: '2026-06-20T09:00:00Z',
      );

      final row = AnalyticsRow.fromExpense(expense);

      expect(row.isIncome, isTrue,
          reason: 'isIncome must not be dropped');
      expect(row.originalAmount, '100.00');
      expect(row.originalCurrency, 'EUR');
      expect(row.universalUsdAmount, '100.00');
    });

    test('universalUsdAmount null → "0"', () {
      final expense = ExpenseModel(
        id: 'exp-3',
        payerId: 'user-1',
        amount: '10.00',
        universalUsdAmount: null,
        currency: 'JPY',
        category: 'Transport',
        isIncome: false,
        description: 'Train ticket',
        createdAt: '2026-06-22T08:00:00Z',
      );

      final row = AnalyticsRow.fromExpense(expense);

      expect(row.universalUsdAmount, '0',
          reason: 'null universalUsdAmount must coerce to "0"');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AnalyticsRow.fromWalletEntry
  // ─────────────────────────────────────────────────────────────────────────
  group('AnalyticsRow.fromWalletEntry', () {
    test('preserves universalUsdAmount and amount', () {
      final entry = WalletEntryModel(
        id: 'we-1',
        userId: 'user-1',
        amount: '75.25',
        universalUsdAmount: '75.25',
        currency: 'USD',
        category: 'Shopping',
        isIncome: false,
        description: 'New shoes',
        createdAt: '2026-06-18T14:00:00Z',
      );

      final row = AnalyticsRow.fromWalletEntry(entry);

      expect(row.universalUsdAmount, '75.25',
          reason: 'universalUsdAmount must survive the mapping');
      expect(row.amount, '75.25');
      expect(row.currency, 'USD');
      expect(row.isIncome, isFalse);
      expect(row.category, 'Shopping');
      expect(row.description, 'New shoes');
      expect(row.createdAt, '2026-06-18T14:00:00Z');
      expect(row.groupId, isNull);
    });

    test('preserves income flag + original currency fields', () {
      final entry = WalletEntryModel(
        id: 'we-2',
        userId: 'user-1',
        amount: '216.00',
        universalUsdAmount: '200.00',
        currency: 'USD',
        originalAmount: '200.00',
        originalCurrency: 'GBP',
        exchangeRateApplied: '1.08',
        category: 'Income',
        isIncome: true,
        description: 'Consulting fee',
        createdAt: '2026-06-25T10:00:00Z',
      );

      final row = AnalyticsRow.fromWalletEntry(entry);

      expect(row.isIncome, isTrue,
          reason: 'isIncome must not be dropped');
      expect(row.originalAmount, '200.00');
      expect(row.originalCurrency, 'GBP');
      expect(row.universalUsdAmount, '200.00');
    });

    test('default universalUsdAmount is "0" (not null)', () {
      final entry = WalletEntryModel(
        id: 'we-3',
        userId: 'user-1',
        amount: '5.00',
        // universalUsdAmount defaults to '0'
        currency: 'EUR',
        category: 'Coffee',
        isIncome: false,
        description: 'Espresso',
        createdAt: '2026-06-22T07:30:00Z',
      );

      final row = AnalyticsRow.fromWalletEntry(entry);

      expect(row.universalUsdAmount, '0',
          reason: 'Wallet entry universalUsdAmount defaults to "0"');
    });
  });
}
