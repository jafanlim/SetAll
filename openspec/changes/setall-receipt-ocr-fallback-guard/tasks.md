# Tasks

## 1. Investigation (report findings before any code)
- [ ] 1.1 Netlify `receipt-ingest` logs around 2026-07-09: find `[receipt] Google Vision …` warn lines; classify the failure (429/400/403/timeout)
- [ ] 1.2 Google Cloud console: Vision key quota + billing state; record verdict in proposal + ledger
- [ ] 1.3 Confirm `bug_reports` INSERT RLS policy accepts an authenticated client insert with `severity='auto'`

## 2. Netlify function (`receipt-ingest.js`)
- [ ] 2.1 Extract `visionOcrWithRetry` wrapper: 1 retry on 429/5xx/network with ~1.5 s backoff; returns `{text, failReason}`
- [ ] 2.2 Thread `ocrFailReason` into response meta alongside existing `ocr` flag; no other response shape changes
- [ ] 2.3 Node unit tests: 429→retry→success; 429→429→`{text:null, failReason:'quota'}`; ok-path unchanged

## 3. Client (`receipt_entry_sheet.dart`)
- [ ] 3.1 Parse `ocr`/`ocrFailReason` from the ingest response into the draft state
- [ ] 3.2 Persistent warning chip when degraded (`ocr:false` && `failReason != 'no_key'`); i18n key `receipt.ocr_degraded_hint` ×6 locales (en/de/es/fr/ka/ru)
- [ ] 3.3 Auto-telemetry: best-effort `bug_reports` insert (severity `auto`, reason, breadcrumbs tail, device/app version; NO image, NO item contents), same try/catch-swallow pattern as bug_report_screen L123–136
- [ ] 3.4 Widget tests: chip on degraded / absent on ok; telemetry fires once and never throws into UI

## 4. Gate + close-out
- [ ] 4.1 `flutter analyze` = 0; full test suite green; surgical diff verified
- [ ] 4.2 Deploy `receipt-ingest` to Netlify (controller or user-gated); live-verify one Georgian receipt end-to-end
- [ ] 4.3 Record incident cause + PR link in ledger; tick this file's boxes in the PR
