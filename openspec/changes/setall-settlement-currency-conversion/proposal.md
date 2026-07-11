# Proposal: Settlement Plan + Member Net Balances — convert USD → display currency

Status: DELIVERED 2026-07-11 — workhorse diff reviewed + landed by controller (branch
`fix/settlement-currency-conversion` off develop `0fbecb8`). analyze 0, 563/563. Clean DeepSeek
delivery, no logic miss. Ships in 1.8.2.
Owner: controller → workhorse (DeepSeek, TDD investigation-first)
Related code:
- `lib/domain/services/settlement_engine.dart` — `SettlementEngine.simplify` (the USD math)
- `lib/data/repositories/setall_repository.dart` — `getSimplifiedDebts` (L4274)
- `lib/core/providers/setall_providers.dart` — `simplifiedDebtsProvider` (L306), `baseCurrencyProvider` (L319)
- `lib/core/services/balance_service.dart` — `getGroupBalanceSummary` (the CORRECT convert-then-net path, L63)
- `lib/core/services/currency_service.dart` — `getRate('USD', base)`
- consumers (all wrong identically today): `group_detail_screen` settlement (L1577), `group_member_balance_helper.computeMemberNetPosition` (L26), `group_info_screen`, `pdf_export_service`

## Why (user report)

On-device, group **Latali**, base currency **GEL**:
- Header "Owed to you": **+GEL 824.21** (correct).
- Settlement Plan rows: Andrei 203.47 + Po 108.80 = **GEL 312.27**.
- 824.21 / 312.27 ≈ **2.64** = the USD→GEL rate.

Every per-user debt (settlement plan **and** the members-card net balances) is understated by the
FX rate. User: "makes me question all math."

## Findings (code-verified 2026-07-11, develop `0fbecb8`)

1. `SettlementEngine.simplify` computes net balances from `universal_usd_amount` (payer,
   L64-72) and `SplitModel.universalUsdOwed` (splits, L74-79) — **USD**. It returns those USD
   magnitudes and stamps `currency` = whatever label the caller passes (L122-127). **No conversion.**
2. `getSimplifiedDebts` passes `currency: baseCurrency` as a **label only** (L4299-4304, L4323-4328).
3. `simplifiedDebtsProvider` comment claims "amounts expressed in the user's base currency"
   (L305) — **false**; they are USD.
4. Contrast — `balance_service.getGroupBalanceSummary` converts each USD entry → base via
   `getRate('USD', baseCurrency)` then nets (L76-82). That is why the header (824.21 GEL) is right
   and the settlement rows (312.27 USD mislabeled GEL) are not. They already agree in USD.
5. Blast radius — everything that reads `simplifiedDebts` amounts is wrong the same way:
   settlement plan; **member net card** `computeMemberNetPosition` sums `t.amount`
   (`group_member_balance_helper.dart:32-33`); group_info settlement; any group PDF rendering debts.
   A single fix at the conversion point heals all consumers.
6. Manifests **only when base ≠ USD** (for USD users, USD net == base). The #5/#6 QA-wave tests
   used USD fixtures and passed; the #5 proposal even asserts "debts are computed in group currency"
   — that premise is false. **The guard test MUST use a non-USD base.**
7. Secondary latent bug: the engine's payer amount falls back to raw `expense['amount']` (group
   currency) when `universal_usd_amount` is null (L66-69), while splits always use `universalUsdOwed`
   (USD). When USD normalization is missing this nets group-currency payer against USD splits — a
   mixed-currency net. Fix must source both sides consistently.

## Proposed change

1. **Convert to the display (base) currency BEFORE the greedy simplification** — mirror the header's
   convert-then-net so the two reconcile. Compute per-member net in USD (as today), convert each
   member's net USD→base with the resolved rate and `round(scale: 2)`, then run the greedy match in
   base. Do **not** multiply the already-rounded per-transaction USD amounts (double-rounding drift).
2. Keep `SettlementEngine` pure + synchronous: thread the resolved `Decimal usdToBaseRate` in from
   `getSimplifiedDebts` (async, can call `currencyService.getRate('USD', base)`). Apply the rate to
   `netBalances` before splitting creditors/debtors. **Rate == Decimal.one when base == USD**
   (byte-identical output for USD users — protect the regression class).
3. Fix the payer/split source mismatch (finding 7): use universal-USD for both sides; when a row
   lacks it, handle both sides consistently (documented fallback), never payer-in-group-currency vs
   split-in-USD.
4. `Decimal` only, no float. `currency` label stays the base currency.

## Acceptance / invariant (the guard — write RED first)

Hermetic, **non-USD base + known clean rate** (e.g. base GEL, USD→GEL = 2.50, whole-number amounts):

1. **Reconciliation (the core):** `Σ(rows where toUserId == me) − Σ(rows where fromUserId == me)`
   == `balance_service` net for the same fixture (`youAreOwed − youOwe`). Exact for the clean-rate
   fixture; general tolerance ≤ (member count) cents.
2. **Per-row:** each row amount == `round(usd_net_segment × rate, 2)`.
3. **Member card:** `computeMemberNetPosition` over the converted debts == the per-member base nets.
4. **USD unchanged:** base == USD ⇒ output identical to current code (rate == 1).
5. The reconciliation test must **fail RED on current code** (demonstrating the ~2.64× gap) and pass
   after the fix.

## Out of scope

Export overhaul (CSV failure, per-group PDF/CSV) — separate openspec later (user decision, 2026-07-11).

## Delivery contract

Deliverable = **diff on the workhorse branch, then STOP**. Do not push / open a PR / edit the ledger.
Controller reviews the actual code, verifies the invariant, and owns push + PR + ledger. Hard gates:
`Decimal`/no-float, surgical (no whole-file reflow, no broad `git add`), `flutter analyze` = 0, full
suite green. Ships in **1.8.2**.
