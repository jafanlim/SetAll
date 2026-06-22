# Tasks: SetAll AI Receipt Ingest

Status: `[ ]` = pending, `[x]` = complete, `[~]` = in-progress

---

## Phase 0 — Foundation (controller, no workhorse code)

- [x] **0.1** Read spec documents in order (proposal → design → spec → tasks)
- [x] **0.2** Read analog files: voice-entry.js, voice_entry_sheet.dart,
  voice_entry_service.dart, setall_repository.dart (addExpense/uploadAttachments),
  auth_config.dart
- [x] **0.3** Confirm OpenAI capability:
  - gpt-4.1-mini supports vision input: **YES** (image_url in messages API)
  - Structured Outputs (json_schema response_format): **YES** (GPT-4.1 family)
  - PDF native support: **NO** — require image (WebP/JPEG). PDFs converted client-side in v2.
  - Signed URL fetch by fn: fn downloads image bytes from Supabase signed URL, encodes as
    base64 data URL for OpenAI API (avoids Netlify body-size limit)
- [x] **0.4** Create openspec files (proposal.md, design.md, spec.md, tasks.md)
- [ ] **0.5** Confirm open decisions with Aleksei before Phase 3+:
  - [ ] Signed-URL vs base64 flow (design recommends signed URL → fn fetches → base64)
  - [ ] Card-owner UX v1 confirmation (free-text label, no group member picker yet)
  - [ ] Rate limit confirmation (10/60s)

---

## Phase 1 — Database (workhorse task)

Depends on: Phase 0 complete

- [x] **1.1** Write migration `supabase/migrations/20260621000001_receipt_memory_tables.sql`
  - Creates `payment_methods`, `merchant_memory`, `item_memory` (exact DDL in spec.md §2)
  - RLS on all three tables per spec §4
  - `is_group_member()` function if not already in a prior migration
  - Run `supabase db push` (or apply via MCP) and verify tables appear

Gate: `flutter analyze` must still exit 0 after this phase (no Dart changes, but verify).

Workhorse brief: see spec.md §2 for exact DDL. Mirror RLS style from existing migrations.
Check existing migrations for `is_group_member` before recreating it.

---

## Phase 2 — Netlify Function (workhorse task)

Depends on: Phase 1 complete

- [x] **2.1** Create `netlify/functions/receipt-ingest.js`
  - Mirror auth gate + rate-limit + CORS from voice-entry.js exactly
  - Rate limit: 10/60s (not 20)
  - Memory retrieval: `merchant_memory` top-5 + `item_memory` top-10 (if groupId present)
  - OpenAI vision call with Structured Outputs (spec.md §1 schema)
  - Server-side validation/clamping (spec.md §1 validation section)
  - last4 → payerLabel lookup against `payment_methods`
  - Escalation path: if `confidence < 0.7`, retry with `gpt-4.1`; max 1 escalation
  - Return 200 draft or needs-clarification shape per spec.md §1
  - Generic error bodies only — no leakage
  - `process.env.OPENAI_API_KEY` — code against name, do not print value

- [x] **2.2** Add `OPENAI_API_KEY` stub to `.env.server` (Aleksei will set the real value):
  ```
  OPENAI_API_KEY=<set-by-aleksei>
  ```

Gate: `node netlify/functions/receipt-ingest.js` must not throw on load.
Deploy to Netlify preview and confirm 401 for unauthenticated POST.

---

## Phase 3 — Flutter Service Layer (workhorse task)

Depends on: Phase 0 open decisions confirmed, Phase 2 deployed to preview

- [ ] **3.1** Add URL constants to `lib/core/config/auth_config.dart`:
  ```dart
  static const String netlifyReceiptIngestUrl =
      'https://setall.app/.netlify/functions/receipt-ingest';
  ```

- [ ] **3.2** Create `lib/core/models/receipt_ingest_result.dart`
  - `ReceiptDraft` model (all money fields as `Decimal`, see spec.md §3)
  - `LineItem` model
  - `ReceiptIngestResponse` model (draft + escalated + imageStoragePath)
  - `fromJson` constructors — parse `amount` as `Decimal.parse(json['amount'])` strictly

- [ ] **3.3** Create `lib/core/services/receipt_ingest_service.dart`
  - `uploadAndIngest(imagePath, {...})` → uploads to `expense-attachments` bucket via
    `_uploadAttachments`-style logic, generates signed URL, POSTs to fn
  - `writeBackMemory({merchantName, category, groupId?, itemName?})` → upserts to
    `merchant_memory` + `item_memory` via Supabase client directly
  - Mirror singleton pattern from VoiceEntryService

Gate: `flutter analyze` exits 0.

---

## Phase 4 — Flutter UI (workhorse task)

Depends on: Phase 3 complete

- [ ] **4.1** Create `lib/features/receipt/presentation/receipt_entry_sheet.dart`
  - States: uploading → processing → confirming → saving → done | error (spec.md §3)
  - `confirming` state: editable form matching voice_entry_sheet.dart confirming layout
    - amount (Decimal text field), currency dropdown, description, category chip, payer,
      date, image thumbnail
  - `error` state: retry button + "Enter manually" TextButton
  - On confirm: call `repo.addExpense(attachmentPaths: [storagePath])` or
    `repo.upsertWalletEntry()` depending on groupId; then `service.writeBackMemory(...)`
  - Invalidate `balanceSummaryProvider`, `recentExpensesProvider` on success

- [ ] **4.2** Add camera trigger in Wallet screen
  - Camera icon button in AppBar or alongside FAB
  - `ImagePicker` (gallery + camera options) → `showModalBottomSheet(ReceiptEntrySheet)`

- [ ] **4.3** Add camera trigger in Group detail screen
  - Alongside existing "+" add-expense button

Gate: `flutter analyze` exits 0. Manual smoke: photograph a café receipt; correct draft
appears; confirm saves expense with image attached.

---

## Phase 5 — Eval Harness (workhorse task)

Depends on: Phase 2 function deployed

- [ ] **5.1** Create `promptfoo/receipt-ingestconfig.yaml`
  - 12+ golden receipt fixtures (spec.md §5 list)
  - Provider: `openai:gpt-4.1-mini` at `temperature: 0.0`
  - Assertions per fixture (amount, currency, category, confidence threshold)

- [ ] **5.2** Add test images to `promptfoo/fixtures/receipts/` (12+ WebP/JPEG files)
  - Use public domain or synthetic receipt images
  - Each image referenced by fixture in the yaml

- [ ] **5.3** Run `npx promptfoo eval --config promptfoo/receipt-ingestconfig.yaml`
  - Must pass ≥ 12/12 before merge
  - Record result in commit message: `promptfoo 12/12`

---

## Phase 6 — Smoke + Merge Gate (controller)

Depends on: Phase 4 UI done, Phase 5 eval ≥ 12/12

- [ ] **6.1** Manual smoke tests:
  - [ ] Café receipt (GEL) → correct draft + image attached to expense
  - [ ] Repeat scan of same merchant → category pre-selected from memory
  - [ ] Known card last4 in group → payer label auto-filled
  - [ ] Blurry receipt → error state shows "Enter manually" fallback
  - [ ] Offline → manual fallback works (no crash)

- [ ] **6.2** `flutter analyze` exits 0 (Stop hook gate)

- [ ] **6.3** Confirm Aleksei has set `OPENAI_API_KEY` in Netlify env before merge to main

- [ ] **6.4** Merge worktree branch to main via `/ship`

- [ ] **6.5** Update `docs/ai-architecture.md` to document receipt-ingest endpoint
  - Also correct Gemini references (Gemini removed 2026-06-21, replaced by OpenAI for new features)
