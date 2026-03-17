/**
 * SetAll — ai-analyst Edge Function
 * ─────────────────────────────────────────────────────────────────────────────
 * Receives a user message + financial context from the Insights Hub and returns
 * a structured AI reply powered by Google Gemini (gemini-2.0-flash).
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

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') ?? ''
const GEMINI_MODEL   = 'gemini-2.0-flash'
const GEMINI_URL     = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, authorization, apikey, x-client-info',
  'Access-Control-Max-Age':       '86400',
}

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
  return `You are the SetAll Neural Engine — a concise, sharp financial AI assistant embedded in the SetAll personal finance dashboard.

The user's financial snapshot (last 90 days of their personal wallet):
- Total spending: $${ctx.totalSpending.toFixed(2)}
- Daily burn rate: $${ctx.dailyBurn.toFixed(2)}/day
- Top categories: ${ctx.topCategories || 'none yet'}
- Total income logged: $${ctx.totalIncome.toFixed(2)}
- Net: $${ctx.net.toFixed(2)}

Recent transactions (newest last):
${ctx.recentRows || 'No transactions loaded yet.'}

You MUST respond with a JSON object matching this exact structure:
{
  "summary": "A concise 1-3 sentence text response to the user.",
  "insights": ["Actionable insight 1", "Actionable insight 2"],
  "chartData": null or a valid Chart.js configuration object: {
    "type": "bar" | "line" | "pie" | "doughnut",
    "data": { "labels": [...], "datasets": [{ "label": "...", "data": [...], "backgroundColor": [...] }] },
    "options": { "responsive": true, "plugins": { "legend": { "display": true } } }
  },
  "actions": []
}

Rules:
- "chartData" should be null unless the user explicitly asks for a chart, graph, or visual.
- When generating chartData, use realistic values derived from the financial snapshot above.
- "actions": include "ADD_TREND" if user asks for a trend/timeline chart, "ADD_DONUT" for category/pie chart, "REFRESH" to reload data, "SIGNOUT" to log out, "PORTAL" to navigate to account portal. Leave empty [] if no action is needed.
- Keep the summary under 3 sentences unless the user explicitly asks for detail.
- Be direct, insightful, and data-driven.`
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  try {
    if (!GEMINI_API_KEY) {
      return new Response(
        JSON.stringify({ reply: 'AI analyst is not configured. Set the GEMINI_API_KEY secret on the Supabase dashboard.' }),
        { status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      )
    }

    const { message, history = [], context } = await req.json()

    if (!message || !context) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: message, context' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      )
    }

    const systemPrompt = buildSystemPrompt(context)

    // Build Gemini contents array from history + current message
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
      generationConfig: {
        maxOutputTokens:  1024,
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
    let rawText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? ''

    // Strip markdown fences if Gemini wraps the JSON despite responseMimeType
    rawText = rawText.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim()

    // Attempt structured parse; fall back to plain text reply
    let structured: { summary: string; insights: string[]; chartData: unknown; actions: string[] } | null = null
    let reply = rawText || 'No response from Gemini.'

    try {
      const parsed = JSON.parse(rawText)
      // Validate required fields
      const summary  = typeof parsed.summary === 'string' ? parsed.summary : reply
      const insights = Array.isArray(parsed.insights) ? parsed.insights.filter((i: unknown) => typeof i === 'string') : []
      const actions  = Array.isArray(parsed.actions)  ? parsed.actions.filter((a: unknown) => typeof a === 'string' && VALID_ACTIONS.has(a as string)) : []

      // Validate chartData if present
      let chartData = null
      if (parsed.chartData && typeof parsed.chartData === 'object') {
        const ct = parsed.chartData
        if (VALID_CHART_TYPES.has(ct.type) && ct.data && typeof ct.data === 'object') {
          chartData = ct
        }
      }

      structured = { summary, insights, chartData, actions }
      reply = summary
    } catch {
      // JSON parse failed — use raw text as plain reply
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
