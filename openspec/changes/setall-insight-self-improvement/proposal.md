## Why
Close the loop: improve the insight system prompt from real behavior signal, using the Karpathy eval-loop pattern (proven at 85% on AutoResearch). Unblocked now that the Spec 5 eval harness exists. Only meaningful once chat has real usage to generate signal.

## What Changes
- Stage 1 (now): behavior-signal capture (insight shown / dismissed / expanded / chat follow-up). New `insight_signal` table, RLS-scoped.
- Stage 2 (deferred): offline variant loop — generate system-prompt variants, score against the LOCKED Spec 5 eval set + behavior signal, promote only if a variant beats baseline on both. Never auto-edit the eval set.

## Impact
- Affected: new migration; lightweight signal capture in chat + insights UI; later an offline tooling script that writes only the active `netlify/functions/ai-analyst.js` prompt (shared by web + mobile since Spec 6).

## Recommendation
Ship Stage 1 now (cheap, starts collecting). Defer Stage 2 until there is enough signal.
