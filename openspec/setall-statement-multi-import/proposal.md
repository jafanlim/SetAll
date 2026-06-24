# Proposal: Bank-Statement Multi-Transaction Import (split + dedupe)

Status: OPEN — not started
Owner: TBD
Related code: `netlify/functions/receipt-ingest.js`, `lib/core/services/receipt_ingest_service.dart`,
`lib/features/receipt/presentation/receipt_entry_sheet.dart`,
`lib/features/settings/presentation/screens/splitwise_import_screen.dart`
Related branch (UNMERGED, local only): `feat/wallet-csv-import` —
"bank statement CSV/PDF ingest, classify, review + commit"

## Why

User fed a **bank statement** into the receipt scanner. It was ingested as **one single
expense** (one "chunk"), not split into the individual transactions on the statement, and
no duplicate-detection ran. A statement is fundamentally a *list* of transactions, not a
single receipt — the current path can't represent that.

## Observed (screenshot 2026-06-24)

Add Wallet Entry screen with the statement image attached, collapsed into ONE entry:
- Amount **-GEL 6098.17** (a balance/net figure, not a single transaction)
- Description **"Bank account statement summary"** — the model *recognized* it was a statement
  but the single-draft schema forced one row
- Category **Other**, Date **2026-06-24** (today, not the real transaction dates), 95% confidence
- A **"Line items / + Add item"** section is already present on this screen (receipt-split
  phase-2 UI) → candidate surface to render the parsed transactions for review, rather than a
  brand-new screen.

## Current Behaviour / Findings

- `receipt-ingest.js` is built for **one receipt → one draft**. Its `RECEIPT_RESPONSE_FORMAT`
  Structured-Output schema returns a *single* `{amount, currency, description, ...}` object.
  It physically cannot emit N transactions, so a statement collapses into one row.
- There IS prior work for this: local branch `feat/wallet-csv-import` adds a bank-statement
  CSV/PDF ingest → classify → review → commit flow, and `splitwise_import_screen.dart` exists.
  **That branch is not merged and not on origin.** main only has commit `6dda66f`
  ("skip duplicate rows + preserve transaction date on import") which is the CSV importer's
  dedupe, *not* wired to the photo/receipt scanner path.
- Net: two disconnected worlds — (a) single-receipt OCR, (b) a half-landed statement importer.
  The user hit (a) expecting (b).

## Proposed Approach

1. **Detect statement vs receipt** server-side in the ingest function (or a new
   `statement-ingest` function): if the document looks like a transaction list (multiple
   dated debit/credit lines), return an **array** of transaction drafts instead of one.
   - Add a `multi: true` response shape: `{ transactions: [ {date, amount, currency,
     description, direction(debit/credit), rawLine}, ... ] }`.
   - Keep the single-receipt path unchanged for actual receipts.
2. **Review screen**: reuse / adapt the `splitwise_import_screen` review UI — a checklist of
   parsed rows the user can edit, toggle, and bulk-confirm before commit (human-in-the-loop).
3. **Dedupe before commit** using the logic already on main (`6dda66f`): match on
   (date + amount + normalized description) against existing wallet entries; pre-uncheck or
   badge rows that look like duplicates; preserve original transaction date.
4. **Decide the canonical importer**: land `feat/wallet-csv-import` properly (rebased, audited
   for the "workhorse committed to main" issues noted in memory) rather than re-implementing.
   The receipt scanner should *route to* it when it detects a statement, not duplicate it.

## Scope

**In:** statement detection, multi-row parse, review+edit UI, dedupe at commit, wire receipt
scanner → statement flow, land the existing CSV importer cleanly.
**Out:** auto-categorization ML beyond current rules; auto-commit without review; multi-account
reconciliation; recurring-charge detection (separate `feat/recurring` work).

## Open Questions

- Reuse `receipt-ingest.js` with a branch, or split into `statement-ingest.js`? (Netlify ~26s
  sync cap — a long statement may need chunking or async.)
- Is `feat/wallet-csv-import` close enough to land, or rebuild on current main?

## Tasks

- [ ] Audit `feat/wallet-csv-import` vs current main; decide land vs rebuild
- [ ] Server: statement detection + array response shape
- [ ] Client: multi-row review/edit screen (adapt splitwise_import_screen)
- [ ] Client: dedupe pass at commit (reuse `6dda66f` logic), preserve dates
- [ ] Route receipt scanner → statement flow on detection
- [ ] Tests: fixture statement (multi-currency, debit/credit) → N rows, dedupe correctness
