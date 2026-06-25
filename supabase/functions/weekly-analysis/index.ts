/**
 * SetAll — weekly-analysis Edge Function  (FEAT-19)
 * ──────────────────────────────────────────────────
 * Runs every Monday 08:00 UTC via pg_cron, or on-demand when
 * called with { userId, onDemand: true } in the request body.
 *
 * Secrets required:
 *   supabase secrets set GROQ_API_KEY="gsk_..."
 *
 * Deploy:
 *   supabase functions deploy weekly-analysis
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const GROQ_API_KEY = Deno.env.get('GROQ_API_KEY') ?? ''
const GROQ_MODEL   = 'llama-3.3-70b-versatile'
const GROQ_URL     = 'https://api.groq.com/openai/v1/chat/completions'
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')              ?? ''
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  try {
    // ── Dual-mode auth gate ──
    // Path A: pg_cron sends x-edge-secret + empty body
    const secretOk = (Deno.env.get('EDGE_SHARED_SECRET') ?? '').length > 0 && (req.headers.get('x-edge-secret') ?? '') === Deno.env.get('EDGE_SHARED_SECRET');

    // Path B: Flutter app sends Authorization: Bearer <user JWT>
    let authedUid: string | null = null;
    if (!secretOk) {
      const authHeader = req.headers.get('Authorization') ?? '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
      if (token) {
        const { data, error } = await createClient(SUPABASE_URL, SERVICE_KEY).auth.getUser(token);
        authedUid = (!error && data?.user) ? data.user.id : null;
      }
    }

    // Fail closed — neither valid secret nor valid JWT
    if (!secretOk && authedUid == null) {
      return new Response(JSON.stringify({ error: 'unauthorized' }), {
        status: 401,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const admin = createClient(SUPABASE_URL, SERVICE_KEY)

    // Parse optional on-demand body
    let onDemandUid: string | null = null
    try {
      const body = await req.json()
      if (body?.onDemand && body?.userId) onDemandUid = body.userId
    } catch (_) { /* cron call — no body */ }

    // Security — JWT path is restricted to the authenticated user
    if (!secretOk && authedUid) onDemandUid = authedUid;

    // Time window: last 7 days
    const now   = new Date()
    const start = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)

    // Fetch target profiles
    let profileQuery = admin.from('profiles').select('id, name')
    if (onDemandUid) {
      profileQuery = profileQuery.eq('id', onDemandUid)
    }
    const { data: profiles, error: profErr } = await profileQuery
    if (profErr || !profiles?.length) {
      return new Response(JSON.stringify({ processed: 0 }), {
        headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
      })
    }

    let processed = 0

    for (const profile of profiles) {
      const uid = profile.id as string

      // Fetch expenses in the last 7 days (personal + group) where user is payer
      const { data: expenses } = await admin
        .from('expenses')
        .select('amount, currency, category, is_income, description, created_at')
        .eq('payer_id', uid)
        .gte('created_at', start.toISOString())
        .lt('created_at', now.toISOString())
        .is('deleted_at', null)

      if (!expenses?.length) continue

      // Compute stats
      const incomeRows  = expenses.filter((e: any) => e.is_income)
      const expenseRows = expenses.filter((e: any) => !e.is_income)

      const totalIncome   = incomeRows.reduce((s: number, r: any) => s + (parseFloat(r.amount) || 0), 0)
      const totalExpenses = expenseRows.reduce((s: number, r: any) => s + (parseFloat(r.amount) || 0), 0)
      const netChange     = totalIncome - totalExpenses
      const currency      = expenses[0]?.currency ?? 'USD'

      // Top categories
      const catTotals: Record<string, number> = {}
      for (const r of expenseRows) {
        const cat = (r.category as string) || 'Other'
        catTotals[cat] = (catTotals[cat] ?? 0) + (parseFloat(r.amount) || 0)
      }
      const sortedCats = Object.entries(catTotals).sort((a, b) => b[1] - a[1])
      const topCategory = sortedCats[0]?.[0] ?? null
      const catSummary  = sortedCats.slice(0, 3)
        .map(([c, v]) => `${c}: ${currency} ${v.toFixed(2)}`).join(', ')

      const fmt = (v: number) => `${currency} ${Math.abs(v).toFixed(2)}`

      // Call Groq
      const prompt = `Income: ${fmt(totalIncome)}, Expenses: ${fmt(totalExpenses)}, Net: ${netChange >= 0 ? '+' : ''}${fmt(netChange)}. Top spending categories: ${catSummary || 'none'}.`

      const groqRes = await fetch(GROQ_URL, {
        method:  'POST',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': `Bearer ${GROQ_API_KEY}`,
        },
        body: JSON.stringify({
          model: GROQ_MODEL,
          temperature: 0.4,
          messages: [
            {
              role: 'system',
              content: 'You are a personal finance analyst. Given this week\'s transactions, provide: (1) 2-3 sentence summary, (2) top category, (3) one actionable tip. Respond ONLY in valid JSON with keys: summary, top_category, tip, sentiment (one of: positive, neutral, negative).',
            },
            { role: 'user', content: prompt },
          ],
        }),
      })

      let structured: any = {}
      try {
        const groqJson = await groqRes.json()
        const text = groqJson?.choices?.[0]?.message?.content ?? '{}'
        structured = JSON.parse(text)
      } catch (_) {
        structured = { summary: `You spent ${fmt(totalExpenses)} this week.`, top_category: topCategory, tip: null, sentiment: 'neutral' }
      }

      // Upsert into ai_insights
      await admin.from('ai_insights').insert({
        user_id:       uid,
        analysis_type: onDemandUid ? 'on_demand' : 'weekly',
        period_start:  start.toISOString(),
        period_end:    now.toISOString(),
        summary:       structured.summary ?? `Weekly summary for ${uid}`,
        top_category:  structured.top_category ?? topCategory,
        net_change:    netChange,
        income_total:  totalIncome,
        expense_total: totalExpenses,
        raw_response:  structured,
      })

      processed++
    }

    return new Response(JSON.stringify({ processed }), {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status:  500,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  }
})
