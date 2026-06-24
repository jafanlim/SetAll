## Why
Subscriptions are the silent budget killer and a top-requested PFM feature. Detect them from existing history; the user confirms. Output feeds budgets (predictable spend) and insights.

## What Changes
- Detection over history via `getPersonalExpenses()` (raw expense list), emitting candidates with confidence. NOT `getWalletEntryTotals` — that returns totals only, not individual rows.
- Confirm/dismiss screen; confirmed rules persisted.
- New `recurring_rules` table, RLS-scoped.

## Impact
- Affected: new migration, detection service, one confirm screen.
- Output consumed by `setall-budgets` and `setall-proactive-alerts`.

## Decision
Heuristic detection (fuzzy description match + amount tolerance + 28–32-day spacing). Groq-assisted is a later fallback gated on real false-negative signal — not v1.
