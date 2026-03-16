/**
 * SetAll — ai-analyst Edge Function
 * ─────────────────────────────────────────────────────────────────────────────
 * Receives a user message + financial context from the Insights Hub and returns
 * an AI reply powered by Google Gemini (gemini-1.5-flash).
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
 *   { reply: string }
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') ?? ''
const GEMINI_MODEL   = 'gemini-1.5-flash-latest'
const GEMINI_URL     = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, authorization',
}

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

You can also control the dashboard. If the user asks for a chart, trend graph, or visual, end your reply with the exact token: [ACTION:ADD_TREND]. If they ask for a category donut or pie chart, end with: [ACTION:ADD_DONUT].
If they ask to refresh data, end with: [ACTION:REFRESH].
If they ask to sign out or log out, end with: [ACTION:SIGNOUT].
If they ask to go to portal or account, end with: [ACTION:PORTAL].

Keep replies under 3 sentences unless the user explicitly asks for detail. Be direct, insightful, and data-driven.`
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
        maxOutputTokens: 300,
        temperature:     0.7,
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
    const reply = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? 'No response from Gemini.'

    console.log(`ai-analyst: replied (${reply.length} chars)`)

    return new Response(
      JSON.stringify({ reply }),
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
