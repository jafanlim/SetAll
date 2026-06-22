# Tasks

## 1. Web (Supabase-direct path)
- [x] 1.0 Prerequisite: `setall-wallet-import-parity` tasks 1.1 (CsvAdapter extraction) and 1.2 (freeze fix) must be complete before this task begins. Do NOT re-spec or re-implement CsvAdapter here.
- [x] 1.1 Generic-CSV adapter + column-mapping UI → normalized rows, consuming `CsvAdapter.parse` from `setall-wallet-import-parity`
- [x] 1.2 Text-PDF adapter: server-side extraction in `ingest.js` using `pdf-parse` npm package (NOT `pdfx` — that is a Dart lib and cannot run in a Netlify fn) → normalized rows
- [x] 1.3 Classification call in `ingest.js` (Groq); category vocabulary = union of `kExpenseCategories` (fixed enum, `expense.dart:5`) AND user-created categories from `getUserCategories` / `user_categories` table; both sources required
- [x] 1.4 Pending-review screen: per-row edit + approve/reject; nothing writes until approved
- [x] 1.5 Commit approved → Supabase via `upsertWalletEntry` (build a `WalletEntryModel` per approved row; freezes `base_currency_amount`, RLS). NOT `addExpense`
- [ ] 1.6 Verify end-to-end on one real bank CSV + one text PDF

## 2. Mobile
- [ ] 2.1 Port flow; add native file picker
- [ ] 2.2 Camera capture for receipts (mobile-only) + image OCR adapter
- [ ] 2.3 Verify iOS SQLite write path + Android match the web commit

## 3. Eval
- [x] 3.1 Add 4–6 sample statements to the Spec 5 eval set; score classification (locked set — only the classify prompt changes)
