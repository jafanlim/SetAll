# Proposal: Mirror My Share of a Shared Expense into My Wallet (opt-in)

Status: OPEN — not started
Owner: TBD
Related code: `lib/features/expenses/presentation/screens/add_expense_screen.dart`
(shares calc ~L199, ~L445-461, `repo.addExpense` call ~L497),
`lib/data/repositories/setall_repository.dart` (`addExpense` L2371, `upsertWalletEntry` L4054,
`_buildOmniActivity` ~L3163)

## Why

When a shared expense is added (e.g. 200 USD paid, split evenly → 100 USD my share), that
personal share is **not** reflected in my wallet/personal ledger. The user wants their actual
out-of-pocket share to appear as a wallet entry — same date, same description — so personal
spend totals are real. With a **human-in-the-loop** confirm (don't auto-create), and logged in
Activities.

## Current Behaviour / Findings

- `add_expense_screen.dart` computes each participant's share (`SplitMode.evenly/shares`,
  ~L199 residual-to-payer, ~L445-461) and saves a **group** expense via `repo.addExpense()`.
- Wallet entries are personal expenses with `group_id IS NULL`, written via
  `repo.upsertWalletEntry()` (L4054) into the `expenses` table.
- There is **no link** between a group expense and a wallet entry. Group spend never flows into
  wallet net. So "what did I personally spend" excludes shared-expense shares.

## Proposed Approach

1. After a shared expense saves successfully, if the **current user is a split participant**
   (owes a share), show a confirm sheet: *"Add your share (100 USD) to your wallet?"* with the
   expense description + date pre-filled. Default action = the user's choice; remember a
   per-session / settings preference ("always / never / ask") to avoid nagging.
2. On confirm, call `upsertWalletEntry()` with: amount = user's share, currency = expense
   currency, date = expense date, description = expense description (prefixed e.g.
   "Share · <desc>"), and a `source_expense_id` link.
3. **Link + dedupe**: store `source_expense_id` on the wallet entry so we can (a) avoid
   double-add if the sheet is confirmed twice, (b) update/remove the mirror if the group
   expense is edited/deleted, (c) badge it in the wallet as "from group X".
4. **Activity log**: emit an activity event for the wallet mirror creation in
   `_buildOmniActivity` (and its inverse on removal).

## Design Decisions To Settle

- **Payer vs participant semantics.** If *I paid* 200 and my share is 100: the wallet should
  reflect my net personal cost = 100 (my share), not 200. If I paid but am not a participant,
  share = 0 → no prompt. Confirm this is the intended model (personal cost = my share, always).
- **Schema:** add nullable `source_expense_id` (FK to `expenses.id`) on wallet entries. Needs a
  Supabase migration + local SQLite column + sync mapping.
- **Edit/delete propagation:** if the group expense changes share amount, prompt to update the
  mirror? Or leave it stale with a "out of sync" badge? (Recommend: update on edit, remove on
  delete, both human-confirmed.)

## Scope

**In:** post-save confirm sheet, opt-in mirror wallet entry, `source_expense_id` link, dedupe,
activity events, edit/delete propagation, ask/always/never preference.
**Out:** mirroring *other* members' shares into *their* wallets (only the current user's);
retroactive backfill of existing group expenses (could be a one-time optional action later).

## Tasks

- [ ] Migration + SQLite column: `expenses.source_expense_id` (nullable, indexed)
- [ ] Repo: `upsertWalletEntry` accepts `sourceExpenseId`; dedupe on it
- [ ] Post-save confirm sheet in add_expense flow (share + date + desc prefilled)
- [ ] Preference: ask / always / never (Settings + per-session memory)
- [ ] Activity events for mirror create/remove
- [ ] Edit/delete propagation from group expense → mirror (confirmed)
- [ ] Wallet UI badge "from group <name>"
- [ ] Tests: even/uneven split, payer-not-participant (no prompt), edit/delete propagation
