# Tasks

## 1. Net computation
- [x] 1.1 Expose per-member group nets from the existing simplified-debts data (Σ to-member − Σ from-member, `Decimal`); reuse `SettlementEngine`/balance-service outputs — no new math path. Implemented as pure `computeMemberNetPosition` in `group_member_balance_helper.dart`.
- [~] 1.2 ≈ default-currency conversion — **N/A in current architecture.** `simplifiedDebtsProvider`/`getSimplifiedDebts` already denominate debts in the user's base (default) currency (`SettlementTransaction.currency = baseCurrency`), so there is no group-currency amount to annotate. The dormant ≈ scaffolding was removed (controller). A group-currency primary + "≈ default" line would need a base→group conversion the pipeline does not produce — **deferred** as an optional follow-up.

## 2. UI (`group_info_screen.dart` members card)
- [x] 2.1 Primary line: net position per member (incl. current user's own row — removed the `m.id != myUid` gate); teal (is owed) / orange (owes) / neutral (settled), in the debts' currency (= user default). `group.isSettled` short-circuit preserved.
- [x] 2.2 Secondary line: existing vs-you detail ("owes you …" / "you owe …") when non-zero. (≈ default-currency portion N/A per 1.2.)

## 3. Tests (TDD-first) — `test/features/groups/group_member_balance_test.dart`
- [x] 3.1 Hermetic: 3-member even-split nets (A is owed 20, B/C owe 10); third-party B↔C debt visible on B and C with A unaffected; settled group ⇒ all settled
- [x] 3.2 Sub-cent net ⇒ "settled up" (no "owes 0.00") — round-to-scale-2-first rule (PR #40); ±0.01 boundary covered
- [~] 3.3 ≈ suppressed when group currency == default — **N/A**: with debts always in the default currency the ≈ line is never emitted (scaffolding removed per 1.2)

## 4. Gate + close-out
- [x] 4.1 `flutter analyze` = 0; full suite green; Decimal-only; surgical diff (members card + pure helper + test)
- [ ] 4.2 On-device verify (user): every member row (incl. yourself, and third-party-only debtors) shows a net position; ledger update + tick boxes in the PR
