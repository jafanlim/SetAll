## Why
Tracking without budgets is a rear-view mirror. Users want per-category monthly limits and live progress. Every input already exists: categories, multi-currency entries, and base-currency normalization (`base_currency_amount`, P58 rate-lock).

## What Changes
- New `budgets` table (per-category and overall), RLS-scoped to `auth.uid()`.
- Current-period spend vs budget, per-category, base-currency normalized. Spend source is determined after a verification step (see design.md and task 1.0).
- Budget set/edit screen; progress indicators on insights + wallet.
- v1: monthly periods, no rollover.

## Impact
- Affected: new migration, Riverpod budget provider, insights + wallet screens.
- No AI. No change to the expense write path.
