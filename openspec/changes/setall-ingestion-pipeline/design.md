# Design

## Decision
**Extract + classify server-side on Netlify (`ingest.js`)**: one extraction path, consistent.
CSV rows are extracted client-side via `CsvAdapter` (from `setall-wallet-import-parity`) and
only normalized rows go to Groq. For PDF and image inputs the raw file is uploaded to `ingest.js`;
PDF text extraction uses `pdf-parse` (Node package) — NOT `pdfx` (a Dart lib; cannot run in a
Netlify fn). Same Spec 4 auth + rate-limit pattern as `ai-analyst.js` and `voice-entry.js`.

## Pipeline
```
input (CSV | text-PDF | image)
  -> adapter -> normalized rows {date, amount, currency, raw_description}
  -> Groq classify (union of kExpenseCategories enum + user-created categories via getUserCategories / user_categories table) + describe
  -> pending-review screen (edit / approve / reject)
  -> commit approved -> upsertWalletEntry (freezes base_currency_amount, RLS) [NOT addExpense — that path does not set base_currency_amount]
```

## Constraints
- Groq key server-side only (Netlify env). Reuse the Spec 4 auth + rate limit (`ingest.js` is a sibling of `ai-analyst.js`).
- PDF extraction: `pdf-parse` npm package in `ingest.js`. `pdfx` is a Dart lib and cannot be used here.
- Classification category vocabulary: union of `kExpenseCategories` (fixed enum in `expense.dart:5`) AND user-created categories fetched via `getUserCategories` / `user_categories` table. Both sources must be included; using only the fixed enum misses user-defined categories.
- Commit reuses `upsertWalletEntry` (builds a `WalletEntryModel` per approved row); no new write logic, no schema change. NOT `addExpense`.
- Optional `import_batches` table only if undo is wanted (defer).

## Out of scope
Scanned-PDF OCR quality tuning beyond the shared image path; auto-commit without review.

## Verification
Web first: CSV + text-PDF end-to-end on a real bank export. Mobile adds native file
picker + camera capture (mobile-only) + image OCR, then verify iOS SQLite write path.
