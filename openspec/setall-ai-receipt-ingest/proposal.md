# Proposal: SetAll AI Receipt Ingest

## Why

Users of SetAll frequently receive paper bills, café receipts, and group invoices. Manually
entering amounts, descriptions, currencies, and splits is friction that kills the habit of
recording every expense. A one-tap "photograph the receipt" flow that pre-fills the expense form
with high accuracy removes that friction, increases data completeness, and differentiates SetAll
from generic manual trackers.

## What Ships (v1)

- **Camera/gallery trigger** in Wallet screen and Group detail screen.
- Flutter compresses the image (WebP, ≤1200 px) and uploads it to Supabase Storage
  (`expense-attachments` bucket), then calls a new Netlify function `receipt-ingest.js`.
- `receipt-ingest.js` retrieves the user's learned memory (last4→card-label,
  merchant→category, group's usual items) from 3 new Supabase tables, injects it as context,
  calls **OpenAI vision with Structured Outputs** (`gpt-4.1-mini` default; one escalation to
  `gpt-4.1` on low confidence), validates/clamps server-side, and returns a draft.
- Flutter shows a **pre-filled, editable confirmation sheet** (mirrors VoiceEntrySheet).
- On confirm, the app saves via existing `repo.addExpense()` / `repo.upsertWalletEntry()` —
  original image attached — and writes back to the three memory tables (the "RAG loop").

## Scope Boundaries

**In v1**
- Single-image scan (JPEG/PNG/HEIC → WebP on device)
- Wallet entry and group expense (even split only in v1)
- Card-owner v1: free-text label; `owner_profile_id` set only when scanning into a group
- Memory write-back to `merchant_memory` + `item_memory` on confirm
- OpenAI as the sole AI provider for this feature

**Out of scope (phase 2+)**
- pgvector embeddings on `item_memory`
- Multi-receipt batch scanning
- Per-line-item split across group members
- Bank-statement / CSV import
- Auto-commit without user confirmation
- Native PDF processing (PDFs converted to image by client in v2)

## Business Justification

- Reduces time-to-entry from ~30 s (manual) to ~5 s (scan + confirm)
- Increases expense recording compliance, improving the accuracy of balance views
- Foundation for future receipt-audit and expense-report features
