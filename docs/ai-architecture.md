# SetAll AI Architecture

## Active AI Paths

### Flutter client (dashboard card + Insights Panel)

- **Endpoint:** `https://setall.app/.netlify/functions/ai-analyst`
- **Auth:** NONE required from caller
- **How Gemini is authenticated:** Netlify environment variable (`process.env.GEMINI_API_KEY`),
  handled entirely server-side. Flutter sends a plain POST with `Content-Type` only.
- **Models:** `gemini-2.5-flash-lite` (chat, 1024t, temp 0.9) /
  `gemini-2.5-flash` (canvas, 8192t, temp 0.2)
- **Request body:** `{ query: string, mode?: 'chat'|'canvas' }`
  - `query` — single pre-formatted string embedding message + financial context + history
  - `mode` — defaults to `'chat'`
- **Response (chat):** `{ report: '{"summary":"..."}', mode: 'chat' }`
  - Parse: `jsonDecode(data['report'])['summary']`
- **Response (canvas):** `{ report: '{"summary":"...","insights":[...],"charts":[...],"actions":[]}', mode: 'canvas' }`
  - Parse: `jsonDecode(data['report'])` → access `summary`, `insights`, `charts`, `actions`
- **Call sites:**
  - `lib/features/dashboard/presentation/screens/dashboard_screen.dart` — `_aiInsightProvider`
  - `lib/features/insights/providers/insights_provider.dart` — `InsightsNotifier.sendMessage()`
- **Migration:** Previously called `supabase/functions/ai-analyst/index.ts` (ARCH-01).
  Reason: persistent `FunctionException(401)` — JWT session race in `FunctionsClient` SDK.

---

### Web portal (web/insights.html)

- **Endpoint:** `/.netlify/functions/ai-analyst` (same function, relative URL)
- **Auth:** NONE — plain `fetch()`, `Content-Type` only
- **Callers:** `web/insights.html:504`

---

## Inactive / Retired

### supabase/functions/ai-analyst/index.ts

- **Status:** Deployed (v14) but not called by any active code.
- **Reason:** Persistent 401 JWT errors (ARCH-01). Retained, not deleted.

---

## Netlify Environment Variables (set in Netlify dashboard)

- `GEMINI_API_KEY` — Gemini API key, used by the function server-side
  - Note: the function also checks `process.env.Gemini` as a fallback alias
- *(No other secrets required for AI functionality)*

---

## Sync Checklist (when changing the AI function)

- Edit `netlify/functions/ai-analyst.js`
- Update response parsing in: `dashboard_screen.dart` + `insights_provider.dart`
- Deploy: `netlify deploy --prod`
- Smoke test: dashboard AI card + Insights Panel on a physical device
