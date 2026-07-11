# Tasks: Settlement currency conversion (USD → display currency)

TDD investigation-first. Write the red reconciliation test BEFORE any production edit.

## 1. Guard tests (RED first)
- [ ] Hermetic fixture: base **GEL**, `USD→GEL = 2.50`, ≥3 members, whole-number USD amounts so
      conversion is exact. Include a third-party debt (A owes B, neither is "me") so the member-card
      path is exercised.
- [ ] Reconciliation test: `Σ(rows to me) − Σ(rows from me)` == balance-service net for the same
      fixture. MUST fail on current code (shows the ~2.5× gap). This is the locked invariant.
- [ ] Per-row test: each settlement amount == `round(usd_net_segment × 2.50, 2)`.
- [ ] Member-card test: `computeMemberNetPosition` over converted debts == per-member base nets.
- [ ] USD-invariance test: base == USD ⇒ identical to current output (rate == 1), no drift.

## 2. Fix
- [ ] Thread a resolved `Decimal usdToBaseRate` into `SettlementEngine.simplify`; apply to
      `netBalances` (convert + `round(scale: 2)`) before splitting creditors/debtors. Keep the engine
      synchronous + pure.
- [ ] `getSimplifiedDebts`: resolve the rate via `currencyService.getRate('USD', baseCurrency)`
      (rate == `Decimal.one` when base == USD) and pass it in. Web + local paths both.
- [ ] Fix payer/split source mismatch: source both sides from universal-USD consistently; documented
      consistent fallback when universal-USD is absent (no group-currency-vs-USD net).
- [ ] Decimal only. `currency` label stays base. No float anywhere.

## 3. Verify (before handoff)
- [ ] All new guard tests green; the reconciliation test that was RED now passes.
- [ ] `flutter analyze` == 0; full suite green (was 557/557 on `0fbecb8`).
- [ ] Surgical diff — no whole-file reflow, no `dart format` sweep, no broad `git add`, tests only in
      test dirs.

## 4. Controller (NOT the workhorse)
- [ ] Review actual code against the invariant; manual sanity vs the Latali numbers (Andrei ≈ 537,
      Po ≈ 287, Σ ≈ 824 GEL at the real rate).
- [ ] Push + PR into develop; tick these tasks in the PR; ledger note; tag any hermetic LOGIC miss
      with `Eval-Task:` / `Eval-DeepSeek: failed` / `Eval-Hermetic:` trailers.
- [ ] Fold into the **1.8.2** release.
