# SetAll AI Architecture

## Providers

- **Groq** (`llama-3.3-70b-versatile`, `llama-3.1-8b-instant`) — powers the AI analyst
  (dashboard card, Insights Panel, web portal) and voice-entry parsing.
- **OpenAI** — standard provider for **new** AI features going forward (vision /
  Structured Outputs), starting with receipt-ingest (`openspec/setall-ai-receipt-ingest`).
- **Gemini** — fully removed. The retired Supabase edge `ai-analyst` (its only caller)
  was deleted; no `GEMINI_API_KEY` is used anywhere.

## Active AI Paths

### AI analyst — `netlify/functions/ai-analyst.js`

- **Endpoint:** `https://setall.app/.netlify/functions/ai-analyst`
- **Provider:** Groq, server-side via `process.env.GROQ_API_KEY`.
- **Models:** `llama-3.1-8b-instant` (chat) / `llama-3.3-70b-versatile` (canvas)
- **Auth:** Bearer token verified via `supabase.auth.getUser`; per-user rate limit 20/60s.
- **Request body:** `{ query: string, mode?: 'chat'|'canvas' }`
  - `query` — single pre-formatted string embedding message + financial context + history
  - `mode` — defaults to `'chat'`
- **Response (chat):** `{ report: '{"summary":"..."}', mode: 'chat' }`
  - Parse: `jsonDecode(data['report'])['summary']`
- **Response (canvas):** `{ report: '{"summary":"...","insights":[...],"charts":[...],"actions":[]}', mode: 'canvas' }`
  - Parse: `jsonDecode(data['report'])` → `summary`, `insights`, `charts`, `actions`
- **Call sites:**
  - `lib/features/dashboard/presentation/screens/dashboard_screen.dart` — `_aiInsightProvider`
  - `lib/features/insights/providers/insights_provider.dart` — `InsightsNotifier.sendMessage()`
  - `web/insights.html` (web portal, relative URL)

### Voice entry — `netlify/functions/voice-entry.js`

- **Endpoint:** `https://setall.app/.netlify/functions/voice-entry`
- **Provider:** Groq (`llama-3.3-70b-versatile`), server-side via `process.env.GROQ_API_KEY`.
- **Auth:** Bearer token verified; per-user rate limit 20/60s.
- **Call site:** `lib/core/services/voice_entry_service.dart`

## Planned

### Receipt ingest — `netlify/functions/receipt-ingest.js` (proposed)

- **Provider:** OpenAI vision + Structured Outputs (`gpt-4.1-mini` default).
- **Spec:** `openspec/setall-ai-receipt-ingest/`. Key: `process.env.OPENAI_API_KEY` (server-only).

## Server Environment Variables (Netlify dashboard / `.env.server`)

- `GROQ_API_KEY` — Groq key, used by ai-analyst + voice-entry server-side.
- `OPENAI_API_KEY` — OpenAI key, used by receipt-ingest (and future AI features) server-side.
- *(No `GEMINI_API_KEY` — Gemini removed.)*

## Sync Checklist (when changing an AI function)

- Edit the relevant `netlify/functions/*.js`.
- Update response parsing in the Flutter/web call sites listed above.
- Deploy: `netlify deploy --prod`.
- Smoke test the affected surface on a physical device.
- Re-run the promptfoo eval suite (`promptfoo/`) before merge.
