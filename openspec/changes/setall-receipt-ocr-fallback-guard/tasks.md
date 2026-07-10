# Tasks

## 1. Investigation (report findings before any code)
- [ ] 1.1 Netlify `receipt-ingest` logs around 2026-07-09: find `[receipt] Google Vision …` warn lines; classify the failure (429/400/403/timeout) — _controller/user infra track; needs Netlify dashboard creds. NOT blocking: the new telemetry makes the next failure self-diagnosing (auto-reports `ocrFailReason`)._
- [ ] 1.2 Google Cloud console: Vision key quota + billing state; record verdict in proposal + ledger — _controller/user infra track; needs GCP console access._
- [x] 1.3 Confirm `bug_reports` INSERT RLS policy accepts an authenticated client insert with `severity='auto'` — _verified via Supabase MCP: policy `users_insert_own` = `WITH CHECK (auth.uid() = user_id)`; `severity` is free-text (no CHECK) so `'auto'` is accepted; `triage_severity` is the CHECK-constrained column and is left unset._

## 2. Netlify function (`receipt-ingest.js`)
- [x] 2.1 Extract `visionOcrWithRetry` wrapper: 1 retry on 429/5xx/network with ~1.5 s backoff; returns `{text, failReason}` (injectable single-attempt callable so retry is testable without network)
- [x] 2.2 Thread `ocrFailReason` into response meta alongside existing `ocr` flag; no other response shape changes
- [x] 2.3 Node unit tests (built-in `node:test` runner, zero deps): 429→retry→success; 429→429→`{text:null, failReason:'quota'}`; 5xx/network retry; 400/403 no-retry; ok-path unchanged — 12/12 green

## 3. Client (`receipt_entry_sheet.dart`)
- [x] 3.1 Parse `ocr`/`ocrFailReason` from the ingest response into the draft state
- [x] 3.2 Persistent warning chip when degraded (`ocr:false` && `failReason != 'no_key'`); i18n key `receipt.ocr_degraded_hint` ×6 locales (en/de/es/fr/ka/ru), native translations
- [x] 3.3 Auto-telemetry: best-effort `bug_reports` insert (severity `auto`, reason, breadcrumbs tail, device/app version; NO image, NO item contents), same try/catch-swallow pattern as bug_report_screen; `user_id = auth.currentUser.id` (RLS), fires at most once per scan via `_telemetrySent` guard
- [x] 3.4 Widget tests: chip on degraded / absent on ok / absent on `no_key` / non-blocking; degraded-condition helper exhaustively covered (14/14 green)

## 4. Gate + close-out
- [x] 4.1 `flutter analyze` = 0; full test suite green (508/508 with `--test-assets`); surgical diff verified (11 files, all expected)
- [ ] 4.2 Deploy `receipt-ingest` to Netlify (controller or user-gated); live-verify one Georgian receipt end-to-end — _post-merge infra step._
- [x] 4.3 Record incident cause + PR link in ledger; tick this file's boxes in the PR
