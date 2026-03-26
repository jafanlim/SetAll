// Supabase Edge Function: send monthly spending digest emails.
// Scheduled via pg_cron: 0 9 1 * * (1st of each month, 09:00 UTC)
// Deploy: supabase functions deploy monthly-digest
// Requires secrets: RESEND_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// ?test=email@address.com — send to ONE user using current month data

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const SUPABASE_URL   = Deno.env.get('SUPABASE_URL')   ?? ''
const SERVICE_KEY    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const FROM_ADDRESS   = 'noreply@setall.app'
const APP_URL        = 'https://setall.app'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
}

const monthName = (d: Date) =>
  d.toLocaleString('en-US', { month: 'long', year: 'numeric' })

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  try {
    const admin = createClient(SUPABASE_URL, SERVICE_KEY)

    // ?test=email@address.com — send to ONE user only, use current month
    const url       = new URL(req.url)
    const testEmail = url.searchParams.get('test')
    const isTest    = !!testEmail

    // Period: test mode = current month, cron = previous calendar month
    const now          = new Date()
    const periodStart  = isTest
      ? new Date(now.getFullYear(), now.getMonth(), 1)
      : new Date(now.getFullYear(), now.getMonth() - 1, 1)
    const periodEnd    = isTest
      ? new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999)
      : new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59, 999)
    const label        = monthName(periodStart)

    // ── Resolve users ──────────────────────────────────────────────────────────
    // profiles table has no email column — email lives in auth.users
    type UserRow = { id: string; name: string | null; email: string }
    let users: UserRow[] = []

    if (isTest) {
      // Find the single auth user with this exact email
      const { data: authData } = await admin.auth.admin.listUsers({ perPage: 1000 })
      const authUser = (authData?.users ?? []).find((u: any) => u.email === testEmail)
      if (!authUser) {
        return new Response(
          JSON.stringify({ error: 'User not found: ' + testEmail }),
          { status: 404, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        )
      }
      const { data: prof } = await admin
        .from('profiles')
        .select('id, name')
        .eq('id', authUser.id)
        .maybeSingle()
      users = [{ id: authUser.id, name: prof?.name ?? null, email: testEmail! }]
    } else {
      // Normal cron — only users with monthly_digest enabled
      const { data: profRows, error: profErr } = await admin
        .from('profiles')
        .select('id, name, notification_preferences')
        .filter("notification_preferences->>'monthly_digest'", 'eq', 'true')
      if (profErr) throw profErr

      const { data: authData } = await admin.auth.admin.listUsers({ perPage: 1000 })
      const emailMap: Record<string, string> = {}
      for (const u of authData?.users ?? []) {
        if (u.email) emailMap[u.id] = u.email
      }
      users = (profRows ?? [])
        .filter((p: any) => emailMap[p.id])
        .map((p: any) => ({ id: p.id, name: p.name ?? null, email: emailMap[p.id] }))
    }

    if (users.length === 0) {
      return new Response(JSON.stringify({ sent: 0 }), {
        headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
      })
    }

    let sent = 0

    for (const user of users) {
      const uid  = user.id
      const name = (user.name ?? '').split(' ')[0] || 'there'

      // ── Expense data from expenses table ──────────────────────────────────
      const { data: rows } = await admin
        .from('expenses')
        .select('amount, is_income, category, universal_usd_amount, currency')
        .eq('payer_id', uid)
        .is('group_id', null)
        .is('deleted_at', null)
        .gte('created_at', periodStart.toISOString())
        .lte('created_at', periodEnd.toISOString())

      const income   = (rows ?? []).filter((r: any) => r.is_income === true  || r.is_income === 1)
      const expenses = (rows ?? []).filter((r: any) => r.is_income === false || r.is_income === 0)

      const totalIncome   = income.reduce((sum: number, r: any) =>
        sum + parseFloat(r.universal_usd_amount ?? r.amount ?? '0'), 0)
      const totalExpenses = expenses.reduce((sum: number, r: any) =>
        sum + parseFloat(r.universal_usd_amount ?? r.amount ?? '0'), 0)
      const net = totalIncome - totalExpenses

      // Top categories (max 5)
      const catTotals: Record<string, number> = {}
      for (const r of expenses) {
        const cat = (r.category as string) || 'Other'
        catTotals[cat] = (catTotals[cat] ?? 0) + parseFloat(r.universal_usd_amount ?? r.amount ?? '0')
      }
      const sortedCats = Object.entries(catTotals).sort((a, b) => b[1] - a[1]).slice(0, 5)

      const fmt = (v: number) => `USD ${Math.abs(v).toFixed(2)}`

      // ── Latest AI insight ─────────────────────────────────────────────────
      const { data: aiRows } = await admin
        .from('ai_insights')
        .select('summary')
        .eq('user_id', uid)
        .eq('analysis_type', 'weekly')
        .order('created_at', { ascending: false })
        .limit(1)
      const aiSummary = aiRows?.[0]?.summary ?? null

      // ── Build HTML ────────────────────────────────────────────────────────
      const html = buildDigestHtml({
        name, label, email: user.email,
        totalIncome, totalExpenses, net,
        sortedCats, aiSummary, fmt,
      })

      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${RESEND_API_KEY}`,
          'Content-Type':  'application/json',
        },
        body: JSON.stringify({
          from:    `SetAll <${FROM_ADDRESS}>`,
          to:      [user.email],
          subject: `Your SetAll summary for ${label}`,
          html,
        }),
      })

      if (res.ok) sent++
    }

    const result = isTest
      ? { sent, test: true }
      : { sent, total: users.length }
    return new Response(JSON.stringify(result), {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status:  500,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  }
})

// ── Email template ────────────────────────────────────────────────────────────
function buildDigestHtml(p: {
  name:          string
  label:         string
  email:         string
  totalIncome:   number
  totalExpenses: number
  net:           number
  sortedCats:    [string, number][]
  aiSummary:     string | null
  fmt:           (v: number) => string
}): string {
  const { name, label, email, totalIncome, totalExpenses, net, sortedCats, aiSummary, fmt } = p

  const netColor  = net >= 0 ? '#14B8A6' : '#F87171'
  const netSign   = net >= 0 ? '+' : '-'
  const netBg     = net >= 0 ? '#0D2B28' : '#2D1515'

  const catRows = sortedCats.length > 0
    ? sortedCats.map(([cat, amt]) =>
        `<tr>
          <td style="padding:8px 0;font-size:13px;color:#CBD5E1;border-bottom:1px solid #1E293B;">${cat}</td>
          <td style="padding:8px 0;font-size:13px;color:#F1F5F9;font-weight:600;text-align:right;border-bottom:1px solid #1E293B;">USD ${amt.toFixed(2)}</td>
        </tr>`
      ).join('')
    : `<tr><td colspan="2" style="padding:12px 0;font-size:13px;color:#475569;text-align:center;">No expense data for this period.</td></tr>`

  const aiSection = aiSummary
    ? `<!-- AI Insight -->
        <tr>
          <td style="padding:0 0 24px;">
            <div style="border-left:3px solid #14B8A6;background:#0F172A;border-radius:0 8px 8px 0;padding:14px 16px;">
              <p style="margin:0 0 6px;font-size:10px;font-weight:700;color:#14B8A6;letter-spacing:1.5px;text-transform:uppercase;">AI Insight</p>
              <p style="margin:0;font-size:13px;color:#CBD5E1;line-height:1.6;">${aiSummary}</p>
            </div>
          </td>
        </tr>`
    : ''

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Your SetAll Summary — ${label}</title>
</head>
<body style="margin:0;padding:0;background:#0F172A;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#0F172A;padding:48px 16px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#1E293B;border:1px solid #334155;border-radius:16px;overflow:hidden;">

        <!-- Header -->
        <tr>
          <td style="background:linear-gradient(135deg,#0F172A 0%,#1a2744 100%);padding:40px 40px 32px;text-align:center;border-bottom:1px solid #334155;">
            <div style="font-size:13px;font-weight:700;color:#14B8A6;letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">SetAll</div>
            <div style="font-size:22px;font-weight:800;color:#F1F5F9;letter-spacing:-0.5px;">Your ${label} Summary</div>
          </td>
        </tr>

        <!-- Body -->
        <tr>
          <td style="padding:40px;">
            <table width="100%" cellpadding="0" cellspacing="0">

              <!-- Greeting -->
              <tr>
                <td style="padding:0 0 24px;">
                  <p style="margin:0;font-size:16px;font-weight:600;color:#F1F5F9;">Hi ${name},</p>
                  <p style="margin:8px 0 0;font-size:14px;color:#94A3B8;line-height:1.6;">Here's your personal spending summary for <strong style="color:#CBD5E1;">${label}</strong>.</p>
                </td>
              </tr>

              <!-- Stat cards -->
              <tr>
                <td style="padding:0 0 24px;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <!-- Income -->
                      <td width="31%" align="center" style="background:#0D2B1E;border:1px solid #166534;border-radius:12px;padding:16px 8px;">
                        <p style="margin:0;font-size:10px;font-weight:700;color:#4ADE80;letter-spacing:1px;text-transform:uppercase;">Income</p>
                        <p style="margin:6px 0 0;font-size:15px;font-weight:800;color:#4ADE80;">+${fmt(totalIncome)}</p>
                      </td>
                      <td width="3%"></td>
                      <!-- Expenses -->
                      <td width="31%" align="center" style="background:#2D1515;border:1px solid #7F1D1D;border-radius:12px;padding:16px 8px;">
                        <p style="margin:0;font-size:10px;font-weight:700;color:#F87171;letter-spacing:1px;text-transform:uppercase;">Expenses</p>
                        <p style="margin:6px 0 0;font-size:15px;font-weight:800;color:#F87171;">-${fmt(totalExpenses)}</p>
                      </td>
                      <td width="3%"></td>
                      <!-- Net -->
                      <td width="31%" align="center" style="background:${netBg};border:1px solid ${net >= 0 ? '#134e4a' : '#7F1D1D'};border-radius:12px;padding:16px 8px;">
                        <p style="margin:0;font-size:10px;font-weight:700;color:${netColor};letter-spacing:1px;text-transform:uppercase;">Net</p>
                        <p style="margin:6px 0 0;font-size:15px;font-weight:800;color:${netColor};">${netSign}${fmt(net)}</p>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>

              <!-- Top categories -->
              <tr>
                <td style="padding:0 0 24px;">
                  <p style="margin:0 0 12px;font-size:12px;font-weight:700;color:#64748B;letter-spacing:1px;text-transform:uppercase;">Top Categories</p>
                  <table width="100%" cellpadding="0" cellspacing="0">
                    ${catRows}
                  </table>
                </td>
              </tr>

              <!-- AI insight -->
              ${aiSection}

              <!-- CTA -->
              <tr>
                <td style="padding:0 0 24px;" align="center">
                  <a href="${APP_URL}"
                     style="display:inline-block;background:#14B8A6;color:#0F172A;font-weight:700;font-size:15px;padding:14px 36px;border-radius:10px;text-decoration:none;letter-spacing:-0.2px;">
                    Open SetAll ↗
                  </a>
                </td>
              </tr>

            </table>
          </td>
        </tr>

        <!-- Footer -->
        <tr>
          <td style="padding:24px 40px;border-top:1px solid #334155;text-align:center;">
            <p style="margin:0;font-size:12px;color:#475569;line-height:1.6;">
              To stop receiving these emails, go to <strong style="color:#64748B;">Settings → Notifications</strong> in the SetAll app.
            </p>
            <p style="margin:8px 0 0;font-size:11px;color:#334155;">
              Sent to ${email} · <a href="${APP_URL}" style="color:#475569;text-decoration:underline;">setall.app</a>
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`
}
