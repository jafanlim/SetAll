# Proposal: Receipt OCR — Stop Silently Degrading to the Hallucinating Vision Path + Auto-Report Every OCR Failure

Status: OPEN — not started (P1, user-reported 2026-07-09)
Owner: controller → workhorse (investigation-first per `phase1-carried-bugs-often-stale` protocol)
Related code: `netlify/functions/receipt-ingest.js` (`googleVisionOcr` L104–133, path selection
L480–496, meta `ocr` flag L557), `lib/features/receipt/presentation/receipt_entry_sheet.dart`,
`lib/features/support/presentation/screens/bug_report_screen.dart` (L122–136 — the `bug_reports`
insert this change reuses), `supabase/functions/bug-triage/index.ts` + DB trigger `trigger_bug_triage`

## Why (user report)

Receipt recognition (Georgian receipts, Google Vision OCR pre-pass) worked for 10–15 receipts,
then one returned gibberish item names — the gpt-4.1-vision hallucination signature on non-Latin
script. The Vision pre-pass is the whole reason Georgian receipts work; when it silently drops
out, output is garbage, the user can't tell why, and we never learn it happened.

**User requirement (2026-07-10):** every OCR failure must be reported through the SAME pipeline
as the bug-report button, automatically, so failure reasons accumulate and can be fixed over time.

## Findings (code-verified 2026-07-10, develop `f4d125d`)

1. **Silent fallback is the root-cause class.** `googleVisionOcr()` returns `null` on **any**
   failure — HTTP non-OK (429 quota/rate, 400 oversized image, 5xx), per-response `error`,
   exception/timeout (L117–131). The caller falls through to the gpt-4.1 **vision** call
   (L494–496) — the exact path the pre-pass exists to avoid. One transient Vision failure ⇒ one
   hallucinated receipt. Matches "10–15 fine, then one gibberish" precisely.
2. **The client can't see which path ran.** The function returns `ocr: ocrUsed` in meta (L557)
   but `lib/` has **zero** handling of it — a degraded draft renders identically to a good one.
3. Failures are logged only to Netlify function logs (`console.warn('[receipt] Google Vision …')`)
   — nobody sees them.
4. Retry exists for OpenAI 429s (L502–505); none for Vision.
5. **Telemetry pipeline already exists and is triage-wired:** the bug-report button inserts into
   Supabase `bug_reports` (client-side, RLS-permitted for authenticated users) → DB trigger
   `trigger_bug_triage` → `bug-triage` edge fn (Vault-keyed since Task 1). Reusing it costs one
   insert call.

## Investigation step (workhorse does FIRST, reports back before coding)

- Pull Netlify `receipt-ingest` logs around 2026-07-09 (daytime Georgia time); find the
  `[receipt] Google Vision HTTP/error/exception` line; classify: 429 (quota/rate), 400 (image
  over Vision's 10 MB limit), 403 (billing/key), or timeout.
- Check Google Cloud console quota/billing for the Vision key (free tier 1000 units/month —
  10–15 receipts/day ≈ exhaustion in ~2–3 months; if it's a quota wall the durable fix is
  billing, and the code changes below are the safety net).
- Record the verdict in this proposal + the ledger.

## Proposed change

1. **Retry Vision once** on transient failure (429/5xx/network) with ~1.5 s backoff. Budget
   fits: Netlify sync cap ~26 s, Vision calls 1–3 s.
2. **Structured failure reason.** `googleVisionOcr` returns `{text|null, failReason?}`;
   response meta gains `ocrFailReason: 'quota' | 'http_<status>' | 'exception' | 'no_key' | null`.
3. **Client warning chip.** In `receipt_entry_sheet.dart`, when the draft arrives `ocr:false`
   with `ocrFailReason != 'no_key'`, show a persistent non-blocking warning:
   "Precise text recognition unavailable — verify item names" (i18n ×6 locales).
4. **Auto-telemetry via the bug-report pipeline.** Same trigger condition as the chip: insert a
   row into `bug_reports` (same client-side insert shape as bug_report_screen L126–135) with:
   - `severity: 'auto'`, `description: 'OCR fallback: <ocrFailReason>'`,
   - `logs`: request id/timestamp, `ocrFailReason`, model used, receipt language hint if known,
     `BugReportService.breadcrumbs` tail,
   - `device_info` + `app_version` as the manual path does.
   Constraints: best-effort try/catch (telemetry must never break the receipt flow — mirror the
   L123–136 pattern); **never include the receipt image or item contents** (privacy); at most
   one report per scan attempt (natural — fires where the draft lands). No new table, no new
   RLS: identical insert path the button already uses. Verify `bug_reports` INSERT policy
   tolerates `severity='auto'` (it's a free-text column — confirm, don't assume).
5. **Keep the fallback** for Latin-script receipts — availability beats purity; the fix is
   visibility + retry + telemetry, not a hard fail.

## Open decisions (controller)

- None blocking. If the investigation shows a hard quota wall, controller raises billing with
  the user as a separate infra action.

## Acceptance

- Extracted "vision with retry" wrapper unit-tested: 429→retry→success; 429→429→null+reason.
- Widget test: chip renders on degraded meta; no chip when `ocr:true`.
- Telemetry test: degraded draft ⇒ exactly one `bug_reports` insert with reason; insert throwing
  never surfaces to the UI.
- `flutter analyze` = 0; full suite green; surgical diff (no reformat of receipt-ingest.js).
- Incident cause from logs recorded back into this spec + ledger.
