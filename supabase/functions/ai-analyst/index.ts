/**
 * RETIRED — superseded by netlify/functions/ai-analyst.js
 * All clients call https://setall.app/.netlify/functions/ai-analyst directly.
 * This Supabase Edge function is no longer invoked and is kept as a stub only.
 * ─────────────────────────────────────────────────────────────────────────────
 * SetAll — ai-analyst Edge Function (RETIRED)
 * ─────────────────────────────────────────────────────────────────────────────
 * Receives a user message + financial context from the Insights Hub and returns
 * a structured AI reply powered by Google Gemini (gemini-2.5-flash).
 *
 * Secrets required:
 *   supabase secrets set GEMINI_API_KEY="AIza..."
 *
 * Deploy:
 *   supabase functions deploy ai-analyst
 *
 * Request body:
 *   {
 *     message:  string,
 *     history:  Array<{ role: 'user' | 'assistant', content: string }>,
 *     context:  {
 *       totalSpending:  number,
 *       dailyBurn:      number,
 *       totalIncome:    number,
 *       net:            number,
 *       topCategories:  string,   // "Groceries: $120.00, Rent: $1200.00, ..."
 *       recentRows:     string,   // newline-delimited transaction log
 *     }
 *   }
 *
 * Response body:
 *   {
 *     reply: string,                // plain-text summary (backwards compat)
 *     structured: {
 *       summary:   string,
 *       insights:  string[],
 *       chartData: { type, data, options } | null,
 *       actions:   string[]          // e.g. ["ADD_TREND", "REFRESH"]
 *     } | null
 *   }
 */

import { serve }        from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const GEMINI_API_KEY  = Deno.env.get('GEMINI_API_KEY') ?? ''
const GEMINI_MODEL    = 'gemini-2.5-flash'
const GEMINI_URL      = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`

const SUPABASE_URL    = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_ANON   = Deno.env.get('SUPABASE_ANON_KEY') ?? ''

const RATE_LIMIT      = 20
const RATE_WINDOW_MS  = 60_000
const MAX_INPUT_CHARS = 8_000

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, authorization, apikey, x-client-info',
  'Access-Control-Max-Age':       '86400',
}

// All safety categories set to BLOCK_NONE — financial context (amounts, debts,
// transactions) can trigger false positives on default thresholds.
const SAFETY_SETTINGS = [
  { category: 'HARM_CATEGORY_HARASSMENT',        threshold: 'BLOCK_NONE' },
  { category: 'HARM_CATEGORY_HATE_SPEECH',       threshold: 'BLOCK_NONE' },
  { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_NONE' },
  { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_NONE' },
  { category: 'HARM_CATEGORY_CIVIC_INTEGRITY',   threshold: 'BLOCK_NONE' },
]

const VALID_CHART_TYPES = new Set(['bar', 'line', 'pie', 'doughnut'])
const VALID_ACTIONS     = new Set(['ADD_TREND', 'ADD_DONUT', 'REFRESH', 'SIGNOUT', 'PORTAL'])

function buildSystemPrompt(ctx: {
  totalSpending: number
  dailyBurn:     number
  totalIncome:   number
  net:           number
  topCategories: string
  recentRows:    string
}): string {
  return `You are the SetAll Neural Engine — a concise, sharp financial AI assistant embedded in the SetAll personal finance dashboard. You analyse real personal expense data and give actionable, data-driven insights. Keep responses focused and professional.

The user's financial snapshot (last 90 days of their personal wallet):
- Total spending: $${ctx.totalSpending.toFixed(2)}
- Daily burn rate: $${ctx.dailyBurn.toFixed(2)}/day
- Top categories: ${ctx.topCategories || 'none yet'}
- Total income logged: $${ctx.totalIncome.toFixed(2)}
- Net (income minus expenses): $${ctx.net.toFixed(2)}

Recent transactions (oldest first):
${ctx.recentRows || 'No transactions loaded yet.'}

You MUST respond with a single JSON object matching this exact structure — no markdown fences, no extra keys:
{
  "summary": "A concise 1-3 sentence text response to the user.",
  "insights": ["Actionable insight 1", "Actionable insight 2"],
  "chartData": null,
  "actions": []
}

CHART RULES (only include chartData when the user explicitly asks for a chart/graph/visual):
- Replace null with a valid Chart.js v4 config: { "type": "bar"|"line"|"pie"|"doughnut", "data": { "labels": [...], "datasets": [{ "label": "...", "data": [...], "backgroundColor": [...] }] }, "options": { "responsive": true, "plugins": { "legend": { "display": true } } } }
- MATH INVARIANT: For pie and doughnut charts the values array MUST sum to exactly 100. Normalise percentages before responding.
- Use realistic values derived only from the financial data above.

ACTION RULES — populate the "actions" array when relevant:
- "ADD_TREND"  → user wants a trend/timeline chart
- "ADD_DONUT"  → user wants a category or pie chart
- "REFRESH"    → user asks to reload their data
- "SIGNOUT"    → user asks to log out
- "PORTAL"     → user asks to go to the account portal
- Leave [] if no action is warranted.

GENERAL RULES:
- Keep the summary under 3 sentences unless detail is explicitly requested.
- Be direct and data-driven. Reference actual numbers from the snapshot.
- Do not fabricate transactions or categories not present in the data.`
}

// ── Pie/doughnut normalisation ───────────────────────────────────────────────
// Gemini occasionally hallucinates chart values that don't sum to 100%.
// This guard ensures Chart.js always receives valid percentage data.
function normalisePieData(chartData: Record<string, unknown>): Record<string, unknown> {
  const type = chartData.type as string
  if (type !== 'pie' && type !== 'doughnut') return chartData
  try {
    const data = chartData.data as Record<string, unknown>
    const datasets = (data.datasets as Array<Record<string, unknown>>).map(ds => {
      const values = ds.data as number[]
      const total  = values.reduce((s, v) => s + v, 0)
      if (total === 0 || Math.abs(total - 100) < 0.5) return ds
      return { ...ds, data: values.map(v => Math.round((v / total) * 10000) / 100) }
    })
    return { ...chartData, data: { ...data, datasets } }
  } catch {
    return chartData
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  try {
    // ── Auth gate: verify JWT via Supabase auth.getUser (signature-checked) ──
    const authHeader  = req.headers.get('authorization') ?? ''
    const bearerToken = authHeader.replace(/^Bearer\s+/i, '')
    if (!bearerToken) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization token.' }),
        { status: 401, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON, {
      global: { headers: { Authorization: `Bearer ${bearerToken}` } },
      auth:   { persistSession: false },
    })
    const { data: { user }, error: authError } = await supabase.auth.getUser(bearerToken)
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authorization token.' }),
        { status: 401, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      )
    }
    const userId = user.id
    console.log(`ai-analyst: authenticated user ${userId}`)

    // ── Per-user rate limit (20 req / 60 s) via ai_rate_limit table ──
    const windowStart = Math.floor(Date.now() / RATE_WINDOW_MS) * (RATE_WINDOW_MS / 1000)
    const { data: rlData, error: rlErr } = await supabase
      .from('ai_rate_limit')
      .upsert(
        { user_id: userId, window_start: windowStart, count: 1 },
        { onConflict: 'user_id,window_start', ignoreDuplicates: false }
      )
      .select('count')
      .single()
    // If upsert returned existing row, increment manually
    let currentCount = rlData?.count ?? 1
    if (!rlErr && currentCount === 1) {
      // Row was newly inserted — count is already 1, nothing extra needed
    } else if (!rlErr) {
      const { data: inc } = await supabase
        .from('ai_rate_limit')
        .update({ count: currentCount + 1 })
        .eq('user_id', userId)
        .eq('window_start', windowStart)
        .select('count')
        .single()
      currentCount = inc?.count ?? currentCount + 1
    }
    if (currentCount > RATE_LIMIT) {
      return new Response(
        JSON.stringify({ error: 'Rate limit exceeded. Try again in a minute.' }),
        { status: 429, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json', 'Retry-After': '60' } }
      )
    }

    if (!GEMINI_API_KEY) {
      return new Response(
        JSON.stringify({ reply: 'AI analyst is not configured. Set the GEMINI_API_KEY secret on the Supabase dashboard.' }),
        { status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      )
    }

    const { message, history = [], context } = await req.json()

    // ── Input cap ──
    if (typeof message === 'string' && message.length > MAX_INPUT_CHARS) {
      return new Response(
        JSON.stringify({ error: 'Query too long. Maximum 8000 characters.' }),
        { status: 413, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      )
    }

    if (!message || !context) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: message, context' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      )
    }

    const systemPrompt = buildSystemPrompt(context)

    // Build Gemini contents — history + current turn.
    // system_instruction is passed as a top-level key (not inside contents).
    const contents = [
      ...history.map((m: { role: string; content: string }) => ({
        role:  m.role === 'user' ? 'user' : 'model',
        parts: [{ text: m.content }],
      })),
      { role: 'user', parts: [{ text: message }] },
    ]

    const geminiBody = {
      system_instruction: { parts: [{ text: systemPrompt }] },
      contents,
      safetySettings: SAFETY_SETTINGS,
      generationConfig: {
        maxOutputTokens:  8192, // FEAT-06: bumped for InsightsPanel full-chat mode
        temperature:      0.4,
        responseMimeType: 'application/json',
      },
    }

    const geminiRes = await fetch(GEMINI_URL, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(geminiBody),
    })

    if (!geminiRes.ok) {
      const err = await geminiRes.json().catch(() => ({}))
      console.error('Gemini API error:', err)
      return new Response(
        JSON.stringify({ reply: `Gemini error: ${err?.error?.message ?? `HTTP ${geminiRes.status}`}` }),
        { status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      )
    }

    const geminiData = await geminiRes.json()

    // ── Thought filter ─────────────────────────────────────────────────────
    // Gemini 2.5 prepends internal reasoning parts with thought:true.
    // Find the first part that has text AND is NOT a thought token.
    const parts: Array<{ text?: string; thought?: boolean }> =
      geminiData?.candidates?.[0]?.content?.parts ?? []
    let rawText = parts.find(p => p.text && p.thought !== true)?.text ?? ''

    // Strip markdown fences in case the model wraps despite responseMimeType
    rawText = rawText.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim()

    // ── Structured parse with validation ──────────────────────────────────
    let structured: { summary: string; insights: string[]; chartData: unknown; actions: string[] } | null = null
    let reply = rawText || 'No response from Gemini.'

    try {
      const parsed = JSON.parse(rawText)
      const summary  = typeof parsed.summary === 'string' ? parsed.summary : reply
      const insights = Array.isArray(parsed.insights) ? parsed.insights.filter((i: unknown) => typeof i === 'string') : []
      const actions  = Array.isArray(parsed.actions)  ? parsed.actions.filter((a: unknown) => typeof a === 'string' && VALID_ACTIONS.has(a as string)) : []

      let chartData = null
      if (parsed.chartData && typeof parsed.chartData === 'object') {
        const ct = parsed.chartData as Record<string, unknown>
        if (VALID_CHART_TYPES.has(ct.type as string) && ct.data && typeof ct.data === 'object') {
          chartData = normalisePieData(ct)
        }
      }

      structured = { summary, insights, chartData, actions }
      reply = summary
    } catch {
      console.warn('ai-analyst: Gemini returned non-JSON, falling back to text reply')
    }

    console.log(`ai-analyst: replied (${reply.length} chars, structured=${structured !== null})`)

    return new Response(
      JSON.stringify({ reply, structured }),
      { status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
    )

  } catch (err) {
    console.error('ai-analyst unexpected error:', err)
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
    )
  }
})
