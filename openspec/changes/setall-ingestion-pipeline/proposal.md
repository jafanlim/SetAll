## Why
CSV import (SetAll format) already ships. Users onboarding real data need bank statements (PDF) and arbitrary bank CSVs, plus receipt capture. One pipeline — extract → classify → describe → review → commit — with swappable input adapters, instead of three one-off importers.

## What Changes
- Input adapters → normalized rows `{date, amount, currency, raw_description}`: generic bank CSV (column mapping), text-PDF statement, image/receipt (OCR; shared by scanned PDFs).
- Classification: Groq maps each row to an existing category + a short description, reusing the chat grounding's category vocabulary. No new taxonomy.
- Pending-review screen: per-row edit + approve/reject; nothing writes until approved.
- Commit approved rows via `upsertWalletEntry` (builds a `WalletEntryModel` per approved row); `base_currency_amount` is frozen at commit time. NOT `addExpense` — that path does not set `base_currency_amount`.

## Impact
- Affected: Flutter import flow + new review screen + column-mapper; a new Netlify fn `ingest.js` (sibling of `ai-analyst.js`, same auth/rate-limit + Groq pattern); Supabase writes via the existing repo.
- Depends on `setall-wallet-import-parity` for `CsvAdapter` (CSV parsing) — task 1.0 of that change is a prerequisite.

## Decision
Extraction location: server-side Netlify (`ingest.js`). Raw statement never leaves device for the CSV path; PDF text extraction runs on the Netlify fn using a Node PDF parser (e.g. `pdf-parse`). See design.md.
