# Design: SetAll AI Receipt Ingest

## Flow

```
Flutter                         Supabase Storage        Netlify fn              OpenAI
  │                                    │                    │                      │
  │─ compress → WebP ──────────────────▶                    │                      │
  │  (AttachmentProcessor.process)     │                    │                      │
  │◀── storePath + signedUrl ──────────│                    │                      │
  │                                    │                    │                      │
  │─ POST /receipt-ingest ─────────────────────────────────▶│                      │
  │  { signedUrl, groupId, currency }  │                    │                      │
  │                                    │                    │─ SELECT memory ──▶ Supabase DB
  │                                    │                    │◀─ card/merchant/item memory
  │                                    │                    │                      │
  │                                    │                    │─ vision + structured output ──▶│
  │                                    │                    │  (gpt-4.1-mini)               │
  │                                    │                    │◀─ ReceiptDraft ───────────────│
  │                                    │                    │                      │
  │                                    │                    │─ validate + clamp    │
  │                                    │                    │─ last4 lookup ──▶ Supabase DB
  │                                    │                    │  (payment_methods)   │
  │                                    │                    │                      │
  │◀─ 200 { draft, escalated } ────────────────────────────│                      │
  │                                    │                    │                      │
  │─ show ReceiptEntrySheet (edit)     │                    │                      │
  │─ user confirms                     │                    │                      │
  │─ repo.addExpense(attachmentPaths)  │                    │                      │
  │─ repo.upsertWalletEntry            │                    │                      │
  │─ write-back merchant_memory        │                    │                      │
  │─ write-back item_memory (group)    │                    │                      │
```

## Model Choice

| Model | Use | Tokens out | Cost/1k |
|---|---|---|---|
| `gpt-4.1-mini` | Default (first attempt) | ≤512 | cheap |
| `gpt-4.1` | Escalation when confidence < 0.7 | ≤512 | 4× |

Maximum **one escalation** per scan. If gpt-4.1 also returns low confidence, return the
gpt-4.1 draft anyway with `escalated: true`; the user can edit.

Structured Outputs enforced via `response_format: { type: "json_schema", ... }` — eliminates
the markdown-fence stripping hack needed in voice-entry.

## The Three Memory Tables (RAG)

### 1. `payment_methods`
Maps `last4` → card label (+ optional group-member profile) for the authenticated user.
On confirm: client writes new card if `last4` not already stored.

```
payment_methods(
  id          uuid pk
  user_id     uuid fk→auth.users (RLS: user_id = auth.uid())
  last4       text  -- 4 digits only, never full PAN
  label       text  -- "Visa 4242", user-editable
  owner_profile_id  uuid nullable fk→profiles
  created_at  timestamptz
  UNIQUE(user_id, last4)
)
```

### 2. `merchant_memory`
Per-user merchant name → category map, reinforced on every confirmed scan.
Retrieved by the fn to suggest category before the model call.

```
merchant_memory(
  id            uuid pk
  user_id       uuid fk→auth.users (RLS: user_id = auth.uid())
  merchant_name text  -- normalized lowercase, trimmed
  category      text
  hit_count     int   default 1
  last_seen_at  timestamptz
  UNIQUE(user_id, merchant_name)
)
```

### 3. `item_memory`
Per-group usual expense items/patterns. Helps pre-select description in repeat group expenses
(e.g. "Pizza" → "Food & drink" for a specific group). RLS requires group membership.

```
item_memory(
  id           uuid pk
  group_id     uuid fk→groups (RLS: is_group_member(group_id))
  item_name    text  -- normalized
  category     text
  hit_count    int   default 1
  last_seen_at timestamptz
  UNIQUE(group_id, item_name)
)
```

## Reuse Map

| Need | Reuse |
|---|---|
| Fn skeleton (auth, rate-limit, CORS) | `voice-entry.js` |
| Image upload to Storage | `_uploadAttachments()` in setall_repository.dart |
| Signed URL generation | `generateAttachmentSignedUrl()` in setall_repository.dart |
| addExpense + attachmentPaths | `addExpense()` (~line 2367) in setall_repository.dart |
| Wallet entry save | `upsertWalletEntry()` (~line 4033) in setall_repository.dart |
| Endpoint URL config | `AuthConfig` in auth_config.dart (add 2 new consts) |
| Service→endpoint plumbing pattern | `VoiceEntryService` in voice_entry_service.dart |
| Confirmation sheet UI pattern | `VoiceEntrySheet` in voice_entry_sheet.dart |
| Decimal for currency | Already project-wide; enforce in all new money fields |

## Trust Boundary

```
TRUSTED                         UNTRUSTED
────────────────────────────── │ ─────────────────────────────
Supabase RLS gates             │ OpenAI model output
payment_methods server lookup  │ last4 from model (ignored)
clamp on amount (0–1M USD)     │ confidence score from model
fn validates all fields        │ merchant name (normalized only)
Flutter edits before save      │ lineItems (informational only)
```

The model **never** determines the card owner. The fn queries `payment_methods` by last4 and
returns the label. The model's last4 extraction is used only to query the table.

## Privacy

- No full card numbers stored anywhere — `last4` column only.
- Receipt image is uploaded to `expense-attachments` (existing bucket, RLS-protected).
- Signed URL is short-lived (1 h) — passed to the fn, never logged.
- Netlify fn does not log request bodies.
- `merchant_name` normalized before storage (lowercase, trimmed, max 100 chars).

## Failure Modes

| Failure | Handling |
|---|---|
| Upload fails (network) | Return error, offer retry or manual entry |
| Signed URL generation fails | Same — fall through to manual |
| OpenAI 429 rate limit | 1 retry after `retry-after`; if still 429, 503 to client |
| OpenAI 500 | Return 500 to client; client shows manual fallback |
| Low confidence after escalation | Return gpt-4.1 draft + `escalated: true`; user can edit |
| JSON parse fails (malformed model output) | Return 500; structured outputs should prevent this |
| amount clamped to 0 | Treat as needs-clarification; return `needsClarification: "amount"` |
| Unknown last4 | `payerLabel: null`; client shows empty payer field |
| item_memory write-back fails | Log, continue — write-back is best-effort |

## Open Decisions

1. **Signed URL vs base64 default** — Design recommends upload-first + signed URL (avoids
   Netlify 6 MB body cap). Confirm with Aleksei before writing Flutter service.
2. **Card-owner UX v1** — Free-text label only; `owner_profile_id` set when scanning into
   a group (member picker). Confirm before writing ReceiptEntrySheet.
3. **Group split v1** — Even split (per-line-item assignment is phase 2). Already confirmed.
4. **Rate limit** — 10 requests/60 s per user (vision is expensive). Voice-entry uses 20.
