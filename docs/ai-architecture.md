# AI Architecture

Two active AI paths exist in this codebase. They serve different clients and must be kept in sync when changing model, prompt structure, or response shape.

---

## Path 1 — Flutter Client (Supabase Edge Function)

**File:** `supabase/functions/ai-analyst/index.ts`  
**Caller:** Flutter app → `lib/features/analytics/` (Insights Hub screen)  
**Invocation:** Direct Supabase Edge Function call with Bearer JWT token  
**URL:** `https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/ai-analyst`

| Property | Value |
|---|---|
| Model | `gemini-2.5-flash` |
| Max tokens | 2048 |
| Temperature | 0.4 |
| Auth | Bearer JWT (Supabase user token, sub claim validated) |
| Response format | `{ reply: string, structured: { summary, insights, chartData, actions } \| null }` |
| Context shape | `{ message, history[], context: { totalSpending, dailyBurn, totalIncome, net, topCategories, recentRows } }` |
| Unique features | Conversation history support, pie/doughnut normalisation, `responseMimeType: application/json`, action tokens (ADD_TREND, ADD_DONUT, REFRESH, SIGNOUT, PORTAL) |

---

## Path 2 — Web Portal (Netlify Function)

**File:** `netlify/functions/ai-analyst.js`  
**Caller:** `web/insights.html` line 504 — `fetch('/.netlify/functions/ai-analyst', ...)`  
**Invocation:** Netlify serverless function, no auth gate  
**URL:** `/.netlify/functions/ai-analyst` (relative, served from Netlify deployment)

| Property | Value |
|---|---|
| Models | `gemini-2.5-flash-lite` (chat mode) / `gemini-2.5-flash` (canvas mode) |
| Max tokens | 1024 (chat) / 8192 (canvas) |
| Temperature | 0.9 (chat) / 0.2 (canvas) |
| Auth | None (public endpoint) |
| Response format | `{ report: string (JSON-encoded), mode: 'chat'\|'canvas' }` |
| Request shape | `{ query: string, mode: 'chat'\|'canvas' }` |
| Unique features | Canvas mode with chart JSON (`summary/insights/charts/actions`), rate-limit 429 handling with retry-after header, two-model routing |

---

## Sync Checklist

When updating either path, apply equivalent changes to the other if relevant:

- **Model change** — update both `GEMINI_MODEL` constant and the `model` variable
- **Prompt change** — keep financial persona and zero-filler rules consistent
- **Response shape change** — update the Flutter `AiAnalystService` parser and the `insights.html` JS response handler
- **Safety settings** — both currently set all categories to `BLOCK_NONE`; keep in sync
