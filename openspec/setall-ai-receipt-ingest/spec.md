# Spec: SetAll AI Receipt Ingest

## §1 Netlify Function — `receipt-ingest.js`

### Endpoint

```
POST /.netlify/functions/receipt-ingest
```

### Auth

Bearer token (Supabase JWT) in `Authorization` header.
Validate via `supabase.auth.getUser(token)` — same pattern as `voice-entry.js`.
Return `401 { error: "unauthorized" }` if absent or invalid.

### Rate Limit

10 requests / 60 s per user (in-memory Map, same pattern as voice-entry).
Return `429 { error: "Rate limit exceeded. Try again in a minute." }` with `Retry-After: 60`.

### CORS

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Allow-Methods: POST, OPTIONS
```
Return `200` for `OPTIONS` preflight.

### Request Body (JSON)

```jsonc
{
  "imageBase64": "<base64>",           // required — receipt image bytes, base64 (no data: prefix)
  "contentType": "image/webp",         // image/webp|jpeg|png|heic; defaults to image/webp
  "groupId": "uuid | null",            // null = wallet entry
  "defaultCurrency": "USD",            // ISO 4217
  "knownCategories": ["Food & drink", "Transport", ...],
  "timezone": "America/New_York"       // IANA tz, used for date parsing
}
```

**Privacy — the image is never stored.** It is sent inline as base64, used only to
extract the draft, and discarded when the request ends. No Supabase Storage, no signed
URL, no attachment on the saved expense. (Client compresses to WebP ≤1200px first, so the
base64 payload stays well under Netlify's request cap.)

Validation:
- `imageBase64` must be a present, non-empty string — return `400` if missing.
- Decoded image > 4 MB — return `413`.
- `contentType` defaults to `image/webp` if absent/unrecognized.
- `defaultCurrency` defaults to `"USD"` if absent.
- `knownCategories` defaults to the standard 8 if absent.

### Memory Retrieval (server-side, before model call)

1. Query `merchant_memory` for top-5 entries by `hit_count` for `user_id`.
2. If `groupId` present: query `item_memory` for top-10 entries for `group_id`.
3. Query `payment_methods` — pass the full list as lookup table (not to the model; used
   post-model for last4 resolution).

### Model Call

**Provider:** OpenAI  
**Default model:** `gpt-4.1-mini`  
**Escalation model:** `gpt-4.1` (only if `draft.confidence < 0.7` on first attempt)  
**Max escalations:** 1

Message structure:
```json
[
  { "role": "system", "content": "<system prompt — see §1.1>" },
  {
    "role": "user",
    "content": [
      { "type": "image_url", "image_url": { "url": "data:<contentType>;base64,<imageBase64>", "detail": "high" } },
      { "type": "text", "text": "<context injection>" }
    ]
  }
]
```

**Structured output schema** (`response_format`):
```json
{
  "type": "json_schema",
  "json_schema": {
    "name": "receipt_draft",
    "strict": true,
    "schema": {
      "type": "object",
      "properties": {
        "amount":        { "type": "string", "description": "Total amount as decimal string, e.g. '45.50'" },
        "currency":      { "type": "string", "description": "ISO 4217 3-letter code" },
        "description":   { "type": "string", "description": "Short label 3-6 words" },
        "category":      { "type": "string" },
        "merchant_name": { "type": "string" },
        "last4":         { "type": ["string", "null"], "description": "Card last 4 digits if visible, else null" },
        "entry_date":    { "type": "string", "description": "ISO date YYYY-MM-DD from receipt, or today" },
        "line_items":    {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name":     { "type": "string" },
              "amount":   { "type": "string" },
              "quantity": { "type": "integer" }
            },
            "required": ["name", "amount", "quantity"],
            "additionalProperties": false
          }
        },
        "confidence":    { "type": "number", "description": "0.0–1.0" },
        "needs_clarification": { "type": ["string", "null"], "enum": ["amount", "currency", "date", null] }
      },
      "required": ["amount", "currency", "description", "category", "merchant_name",
                   "last4", "entry_date", "line_items", "confidence", "needs_clarification"],
      "additionalProperties": false
    }
  }
}
```

### §1.1 System Prompt (canonical)

```
You are a receipt parser for the SetAll expense-tracking app.
Extract structured data from the receipt image.

Rules:
- amount: the TOTAL amount paid (after tax, tips, discounts). Decimal string, e.g. "45.50".
- currency: 3-letter ISO code. Infer from symbol ($→USD, €→EUR, £→GBP, ₾→GEL, ₽→RUB, ¥→CNY).
  If ambiguous use defaultCurrency from context.
- description: merchant name or top item, 3-6 words, in the receipt's language.
- category: pick exactly one from knownCategories.
- merchant_name: normalized merchant/store name.
- last4: last 4 digits of the card used, if visible on receipt. null if not visible.
  NEVER guess or invent a last4. Extract only if clearly printed.
- entry_date: date from receipt in YYYY-MM-DD. If not readable use today's date from context.
- line_items: array of individual line items (name, amount, quantity). Empty array if not parseable.
- confidence: your confidence 0.0–1.0 that the amount and currency are correct.
- needs_clarification: "amount" if total is unreadable, "currency" if indeterminate, "date" if
  date is critical and missing, null otherwise.

Merchant memory hints (learned from user's history):
{{merchant_hints}}

Group item hints (for group_id {{groupId}}):
{{item_hints}}

Today's date: {{today}}  Timezone: {{timezone}}  Default currency: {{defaultCurrency}}
```

### Server-Side Validation / Clamping

After model response:
1. Parse `amount` as Decimal — if NaN or ≤ 0: set `needs_clarification: "amount"`.
2. Clamp `amount` to `[0.01, 1_000_000]` (USD-equivalent sanity cap).
3. Verify `currency` is a 3-letter uppercase string — fallback to `defaultCurrency`.
4. Truncate `description` to 120 chars.
5. If `last4` present: look up `payment_methods` table (for `user_id`) — return `payerLabel`
   and `payerProfileId` from the row; if not found, return `payerLabel: null`.
6. If `category` not in `knownCategories`: fallback to `"General"`.

### Response Body (200 OK)

```jsonc
{
  "draft": {
    "amount": "45.50",              // Decimal string — NEVER a float
    "currency": "USD",
    "description": "Blue Bottle Coffee",
    "category": "Food & drink",
    "isIncome": false,
    "merchantName": "Blue Bottle Coffee",
    "last4": "4242",               // null if not on receipt
    "payerLabel": "Visa 4242",     // null if last4 unknown
    "payerProfileId": null,        // uuid if matched in group, else null
    "lineItems": [
      { "name": "Latte", "amount": "5.50", "quantity": 1 }
    ],
    "entryDate": "2026-06-21",
    "confidence": 0.95
  },
  "escalated": false               // true if gpt-4.1 was used
}
```

### Needs-Clarification Response (200 OK)

```jsonc
{
  "needsClarification": "amount",   // "amount" | "currency" | "date"
  "partial": { /* same shape as draft, fields filled where known */ }
}
```

### Error Responses

| Code | Body | Condition |
|---|---|---|
| 400 | `{ "error": "bad_request" }` | Missing/empty `imageBase64` |
| 401 | `{ "error": "unauthorized" }` | Missing or invalid Bearer token |
| 413 | `{ "error": "image_too_large" }` | Decoded image > 4 MB |
| 429 | `{ "error": "rate_limit_exceeded" }` + `Retry-After: 60` | >10 req/60s |
| 500 | `{ "error": "parse_failed" }` | Model error, JSON parse failure, or unhandled exception |
| 503 | `{ "error": "upstream_unavailable" }` | OpenAI 429 persists after 1 retry |

**Generic error bodies only** — no stack traces, no internal paths, no model messages leaked.

### Secrets

- `OPENAI_API_KEY` — env var only; provisioned by Aleksei in Netlify dashboard + `.env.server`.
  Code references `process.env.OPENAI_API_KEY` only — never log, print, or include in responses.
  If absent: return `500 { error: "parse_failed" }`.
- `SUPABASE_URL`, `SUPABASE_ANON_KEY` — same pattern as voice-entry.js.

---

## §2 Database Schema

### Migration file name

`supabase/migrations/20260621000001_receipt_memory_tables.sql`

### payment_methods

```sql
create table payment_methods (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  last4            text not null check (last4 ~ '^[0-9]{4}$'),
  label            text not null,
  owner_profile_id uuid references profiles(id) on delete set null,
  created_at       timestamptz not null default now(),
  constraint payment_methods_user_last4_unique unique(user_id, last4)
);

alter table payment_methods enable row level security;
create policy "users manage own payment_methods"
  on payment_methods for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
```

### merchant_memory

```sql
create table merchant_memory (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  merchant_name text not null,
  category      text not null,
  hit_count     int  not null default 1 check (hit_count > 0),
  last_seen_at  timestamptz not null default now(),
  constraint merchant_memory_user_merchant_unique unique(user_id, merchant_name)
);

alter table merchant_memory enable row level security;
create policy "users manage own merchant_memory"
  on merchant_memory for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
```

### item_memory

```sql
create table item_memory (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references groups(id) on delete cascade,
  item_name    text not null,
  category     text not null,
  hit_count    int  not null default 1 check (hit_count > 0),
  last_seen_at timestamptz not null default now(),
  constraint item_memory_group_item_unique unique(group_id, item_name)
);

alter table item_memory enable row level security;
create policy "group members read/write item_memory"
  on item_memory for all
  using  (is_group_member(group_id))
  with check (is_group_member(group_id));
```

Note: `is_group_member(uuid)` must exist. If not, create it in the same migration:
```sql
create or replace function is_group_member(p_group_id uuid)
returns boolean language sql security definer as $$
  select exists (
    select 1 from group_members
    where group_id = p_group_id and user_id = auth.uid()
  );
$$;
```

---

## §3 Flutter Config

### AuthConfig additions (`lib/core/config/auth_config.dart`)

```dart
static const String netlifyReceiptIngestUrl =
    'https://setall.app/.netlify/functions/receipt-ingest';

static const String netlifyReceiptMemoryUrl =
    'https://setall.app/.netlify/functions/receipt-memory';
```

### ReceiptIngestService (`lib/core/services/receipt_ingest_service.dart`)

```dart
class ReceiptIngestService {
  // ingest(imagePath, {groupId, defaultCurrency, knownCategories, timezone})
  //   → reads the LOCAL scanned image, base64-encodes it, POSTs to the fn, returns
  //     ReceiptIngestResponse. NO upload, NO Storage — the image is never persisted.
  //
  // writeBackMemory({merchantName, category, groupId, itemName})
  //   → upserts merchant_memory + item_memory via Supabase client directly
}
```

### ReceiptIngestResponse model

```dart
class ReceiptIngestResponse {
  final ReceiptDraft? draft;
  final bool escalated;
  final String? needsClarification;  // "amount"|"currency"|"date" — present instead of draft
  final ReceiptDraft? partial;       // present with needsClarification
}

class ReceiptDraft {
  final Decimal amount;        // NEVER double
  final String currency;
  final String description;
  final String category;
  final bool isIncome;
  final String merchantName;
  final String? last4;
  final String? payerLabel;
  final String? payerProfileId;
  final List<LineItem> lineItems;
  final DateTime entryDate;
  final double confidence;
}
```

### ReceiptEntrySheet States

Enum `ReceiptEntryState`:
- `scanning` — native document scanner active (capture/crop/de-skew on device)
- `processing` — base64 + fn call in progress
- `confirming` — pre-filled form shown, user can edit all fields
- `saving` — `repo.addExpense()` / `repo.upsertWalletEntry()` in progress
- `done` — auto-dismiss after 1.2 s
- `error` — shows retry button + "enter manually" fallback

### Flutter Behavioral Requirements

- **Decimal everywhere**: `amount` from the response is parsed as `Decimal.parse(draft.amount)`.
  Never use `double.parse`. The confirm form field stores edits as text and parses to `Decimal`
  on save.
- **Human in the loop — pre-fill only**: the draft is a suggestion, never authoritative.
  Every field is editable before confirm: amount, currency, description, category, payer, date,
  and the **line items** (add / edit / remove rows). The user can change everything.
- **No image stored**: the scanned image is shown in the confirm sheet from the on-device file
  for reference only; it is NOT uploaded and NOT attached to the saved expense.
- **Write-back on confirm**: after successful save, call `service.writeBackMemory(...)` — this is
  best-effort (fire-and-forget, errors logged not thrown).
- **Native capture**: use the platform document scanner (iOS VisionKit / Android ML Kit) via a
  Flutter plugin; fall back to the plain image picker on web/unsupported.
- **Offline fallback**: if the scan or fn call fails, show "Enter manually" button that dismisses
  the sheet and opens the standard manual entry flow.
- **Trigger points**:
  - Wallet screen: camera icon in FAB or AppBar action
  - Group detail screen: camera icon alongside the existing "+" expense button

---

## §4 RLS Requirements

| Table | Policy | Gate |
|---|---|---|
| `payment_methods` | All operations | `user_id = auth.uid()` |
| `merchant_memory` | All operations | `user_id = auth.uid()` |
| `item_memory` | All operations | `is_group_member(group_id)` |
| `expense-attachments` bucket | Read | existing RLS (owner or group member) |

No service-role key used client-side. The Netlify fn uses `SUPABASE_ANON_KEY` with the
user's JWT (same as voice-entry.js) — RLS governs all DB access from the fn.

---

## §5 Eval Requirements

- promptfoo config: `promptfoo/receipt-ingestconfig.yaml`
- Provider: direct OpenAI `gpt-4.1-mini` at `temperature: 0.0`
- **≥ 12 golden receipt fixtures** covering:
  - Café receipt (GEL) → correct total, category "Food & drink"
  - Restaurant with tip → total includes tip
  - Supermarket multi-item → largest-item category wins
  - Receipt in USD with last4 visible → last4 extracted
  - Receipt in EUR → currency extracted, not defaultCurrency
  - Handwritten receipt (low confidence) → `confidence < 0.7`, triggers escalation path
  - Receipt with date printed → `entryDate` from receipt, not today
  - Blurry / unreadable amount → `needsClarification: "amount"`
  - Georgian receipt → description in Georgian
  - Russian receipt → description in Russian
  - Group hotel bill (AED) → amount correct, category "Travel"
  - UAE taxi → category "Transport", currency AED
- Record pass count in commit message: e.g. `promptfoo 12/12`

---

## §6 Commit Message Footer

All commits for this feature must include:
```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```
