// Supabase Edge Function: send monthly spending digest emails.
// Scheduled via pg_cron: 0 9 1 * * (1st of each month, 09:00 UTC)
// Deploy: supabase functions deploy monthly-digest --no-verify-jwt
// Requires secrets: RESEND_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// ?test=email@address.com — send to EXACTLY ONE user, uses current month data.
//   Returns early — cron path never runs in test mode.

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

type Profile = { id: string; email: string; full_name: string; lang: string }

const LANG_LOCALE: Record<string, string> = {
  en: 'en-US',
  ru: 'ru-RU',
  de: 'de-DE',
  es: 'es-ES',
  fr: 'fr-FR',
  ka: 'ka-GE',
}

const SUBJECT_TMPL: Record<string, string> = {
  en: 'Your SetAll summary for {month}',
  ru: 'Ваш отчёт SetAll за {month}',
  de: 'Deine SetAll-Zusammenfassung für {month}',
  es: 'Tu resumen de SetAll para {month}',
  fr: 'Votre résumé SetAll pour {month}',
  ka: 'თქვენი SetAll შეჯამება {month}-სთვის',
}

const monthName = (d: Date, lang = 'en') => {
  const locale = LANG_LOCALE[lang] ?? 'en-US'
  return d.toLocaleString(locale, { month: 'long', year: 'numeric' })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  try {
    const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_KEY)
    const url           = new URL(req.url)
    const testEmail     = url.searchParams.get('test')

    // ── TEST MODE ──────────────────────────────────────────────────────────────
    // Sends to exactly ONE user. Returns early — cron logic never runs.
    if (testEmail) {
      const { data: { users: allUsers } } = await supabaseAdmin.auth.admin.listUsers()
      const authUser = (allUsers ?? []).find((u: any) => u.email === testEmail)
      if (!authUser) {
        return new Response(
          JSON.stringify({ error: 'User not found', email: testEmail }),
          { status: 404, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        )
      }
      const { data: testProfRow } = await supabaseAdmin
        .from('profiles')
        .select('language_code')
        .eq('id', authUser.id)
        .maybeSingle()
      const testProfile: Profile = {
        id:        authUser.id,
        email:     authUser.email ?? testEmail,
        full_name: authUser.user_metadata?.full_name ?? authUser.user_metadata?.name ?? testEmail,
        lang:      testProfRow?.language_code ?? 'en',
      }
      const ok = await sendDigestForUser(supabaseAdmin, testProfile, true)
      return new Response(
        JSON.stringify({ sent: ok ? 1 : 0, test: true, email: testEmail }),
        { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
      )
      // STOP HERE — cron logic never runs in test mode
    }

    // ── CRON MODE ──────────────────────────────────────────────────────────────
    // Only runs when ?test= is absent.
    // notification_preferences->>'monthly_digest' stored in profiles table.
    const { data: profRows, error: profErr } = await supabaseAdmin
      .from('profiles')
      .select('id, name, notification_preferences, language_code')
      .filter("notification_preferences->>'monthly_digest'", 'eq', 'true')
    if (profErr) throw profErr

    const { data: { users: cronUsers } } = await supabaseAdmin.auth.admin.listUsers()
    const emailMap: Record<string, string> = {}
    for (const u of cronUsers ?? []) {
      if (u.email) emailMap[u.id] = u.email
    }

    let sent = 0
    for (const p of profRows ?? []) {
      if (!emailMap[p.id]) continue
      const profile: Profile = {
        id:        p.id,
        email:     emailMap[p.id],
        full_name: p.name ?? emailMap[p.id],
        lang:      p.language_code ?? 'en',
      }
      const ok = await sendDigestForUser(supabaseAdmin, profile, false)
      if (ok) sent++
    }

    return new Response(
      JSON.stringify({ sent, total: (profRows ?? []).length }),
      { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
    )
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status:  500,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  }
})

// ── Per-user digest logic ─────────────────────────────────────────────────────
async function sendDigestForUser(
  supabaseAdmin: any,
  profile: Profile,
  isTest: boolean
): Promise<boolean> {
  const now         = new Date()
  const periodStart = isTest
    ? new Date(now.getFullYear(), now.getMonth(), 1)
    : new Date(now.getFullYear(), now.getMonth() - 1, 1)
  const periodEnd   = isTest
    ? new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999)
    : new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59, 999)
  const label       = monthName(periodStart, profile.lang)

  // ── Personal wallet expenses (group_id IS NULL) ──────────────────────────
  const { data: walletRows } = await supabaseAdmin
    .from('expenses')
    .select('amount, is_income, category, universal_usd_amount, currency')
    .eq('payer_id', profile.id)
    .is('group_id', null)
    .is('deleted_at', null)
    .gte('created_at', periodStart.toISOString())
    .lte('created_at', periodEnd.toISOString())

  // ── Group expenses (group_id IS NOT NULL, user is payer) ────────────────
  const { data: groupRows } = await supabaseAdmin
    .from('expenses')
    .select('amount, is_income, category, universal_usd_amount, currency')
    .eq('payer_id', profile.id)
    .not('group_id', 'is', null)
    .is('deleted_at', null)
    .gte('created_at', periodStart.toISOString())
    .lte('created_at', periodEnd.toISOString())

  const toAmt = (r: any) => parseFloat(r.universal_usd_amount ?? r.amount ?? '0')
  const isExp = (r: any) => r.is_income === false || r.is_income === 0
  const isInc = (r: any) => r.is_income === true  || r.is_income === 1

  const walletExpRows = (walletRows ?? []).filter(isExp)
  const groupExpRows  = (groupRows  ?? []).filter(isExp)

  const walletTotal = walletExpRows.reduce((s: number, r: any) => s + toAmt(r), 0)
  const groupTotal  = groupExpRows.reduce((s: number,  r: any) => s + toAmt(r), 0)

  const totalIncome   = [...(walletRows ?? []), ...(groupRows ?? [])].filter(isInc)
    .reduce((s: number, r: any) => s + toAmt(r), 0)
  const totalExpenses = walletTotal + groupTotal
  const net           = totalIncome - totalExpenses
  // Clamp near-zero to avoid -0.00
  const displayNet    = Math.abs(net) < 0.005 ? 0 : net

  // Top 5 categories — combined wallet + group
  const catTotals: Record<string, number> = {}
  for (const r of [...walletExpRows, ...groupExpRows]) {
    const cat = (r.category as string) || 'Other'
    catTotals[cat] = (catTotals[cat] ?? 0) + toAmt(r)
  }
  const topCategories = Object.entries(catTotals)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([name, total]) => ({ name, total }))

  // ── Latest AI insight ────────────────────────────────────────────────────────
  const { data: insight } = await supabaseAdmin
    .from('ai_insights')
    .select('summary, top_category, recommendation')
    .eq('user_id', profile.id)
    .eq('analysis_type', 'weekly')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  // ── Build + send HTML ────────────────────────────────────────────────────────
  const html = buildDigestHtml({
    profile, label,
    totalIncome, totalExpenses, displayNet,
    walletTotal, groupTotal,
    topCategories, insight: insight ?? null,
  })

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${RESEND_API_KEY}`,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify({
      from:    `SetAll <${FROM_ADDRESS}>`,
      to:      [profile.email],
      subject: (SUBJECT_TMPL[profile.lang] ?? SUBJECT_TMPL['en']).replace('{month}', label),
      html,
    }),
  })

  return res.ok
}

// ── Email template ────────────────────────────────────────────────────────────
// Colors match send-welcome-email exactly:
//   Page bg:       #0F172A
//   Card:          #1E293B, border 1px solid #334155
//   Header:        linear-gradient(135deg,#0F172A 0%,#1a2744 100%)
//   Text primary:  #F1F5F9
//   Text body:     #CBD5E1
//   Text muted:    #94A3B8, #64748B
//   Teal accent:   #14B8A6
//   CTA:           bg #14B8A6, color #0F172A, border-radius 10px
//   Footer border: 1px solid #334155, text #475569
function buildDigestHtml(p: {
  profile:       Profile
  label:         string
  totalIncome:   number
  totalExpenses: number
  displayNet:    number
  walletTotal:   number
  groupTotal:    number
  topCategories: { name: string; total: number }[]
  insight:       { summary: string; top_category?: string; recommendation?: string } | null
}): string {
  const { profile, label, totalIncome, totalExpenses, displayNet, walletTotal, groupTotal, topCategories, insight } = p

  const firstName  = (profile.full_name ?? '').split(' ')[0] || 'there'
  const netColor   = displayNet >= 0 ? '#14B8A6' : '#F87171'
  const netBg      = displayNet >= 0 ? '#0D2B28' : '#2D1515'
  const netBorder  = displayNet >= 0 ? '#134e4a' : '#DC2626'
  const netSign    = displayNet >= 0 ? '+' : '-'
  const fmt        = (v: number) => `USD ${Math.abs(v).toFixed(2)}`
  const netFmt     = `${netSign}${fmt(displayNet)}`

  // ── QuickChart bar chart (only when categories exist) ──────────────────────
  const chartSection = topCategories.length > 0 ? (() => {
    const chartConfig = {
      type: 'bar',
      data: {
        labels:   topCategories.map(c => c.name),
        datasets: [{
          label:           'USD',
          data:            topCategories.map(c => parseFloat(c.total.toFixed(2))),
          backgroundColor: '#14B8A6',
          borderRadius:    6,
        }],
      },
      options: {
        plugins: { legend: { display: false } },
        scales: {
          x: {
            ticks: { color: '#94A3B8', font: { size: 11 } },
            grid:  { color: '#1E293B' },
          },
          y: {
            min: 0,
            ticks: {
              color: '#94A3B8',
              font: { size: 11 },
              callback: 'function(v){return "USD "+v.toFixed(0)}',
            },
            grid: { color: '#1E293B' },
          },
        },
      },
    }
    const chartUrl = 'https://quickchart.io/chart?w=500&h=200&bkg=%230F172A&c='
      + encodeURIComponent(JSON.stringify(chartConfig))
    return `
              <!-- Chart -->
              <tr>
                <td style="padding:0 0 24px;">
                  <p style="margin:0 0 12px;font-size:12px;font-weight:700;color:#64748B;letter-spacing:1px;text-transform:uppercase;">Spending by Category</p>
                  <img src="${chartUrl}" width="440" height="175" alt="Spending by category"
                    style="display:block;border-radius:12px;margin:0 auto;max-width:100%;" />
                </td>
              </tr>`
  })() : `
              <!-- No data -->
              <tr>
                <td style="padding:0 0 24px;text-align:center;">
                  <p style="margin:0;font-size:14px;color:#475569;">No expenses recorded for ${label}.</p>
                </td>
              </tr>`

  // ── Category table (top 5 rows) ─────────────────────────────────────────────
  const catRows = topCategories.length > 0
    ? topCategories.map(({ name: cat, total: amt }, i) =>
        `<tr>
          <td style="padding:9px 12px;font-size:13px;color:#CBD5E1;background:${i % 2 === 0 ? '#1E293B' : '#0F172A'};">${cat}</td>
          <td style="padding:9px 12px;font-size:13px;color:#14B8A6;font-weight:600;text-align:right;background:${i % 2 === 0 ? '#1E293B' : '#0F172A'};">USD ${amt.toFixed(2)}</td>
        </tr>`
      ).join('')
    : ''

  // ── AI insight section ──────────────────────────────────────────────────────
  const aiSection = insight
    ? `
              <!-- AI Insight -->
              <tr>
                <td style="padding:0 0 24px;">
                  <div style="border-left:3px solid #14B8A6;padding:16px 20px;background:#0D2B1E;border-radius:0 8px 8px 0;">
                    <div style="color:#14B8A6;font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;margin-bottom:8px;">AI Insight</div>
                    <div style="color:#F1F5F9;font-size:15px;line-height:1.6;">${insight.summary}</div>
                    ${insight.recommendation
                      ? `<div style="color:#94A3B8;font-size:14px;margin-top:8px;">💡 ${insight.recommendation}</div>`
                      : ''}
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

        <!-- Header — matches send-welcome-email gradient exactly -->
        <tr>
          <td style="background:linear-gradient(135deg,#0F172A 0%,#1a2744 100%);padding:40px 40px 32px;text-align:center;border-bottom:1px solid #334155;">
            <div style="font-size:36px;margin-bottom:8px;">⚖️</div>
            <div style="font-size:24px;font-weight:800;color:#F1F5F9;letter-spacing:-0.5px;">SetAll</div>
            <div style="font-size:12px;color:#64748B;margin-top:4px;letter-spacing:0.5px;text-transform:uppercase;">${label} Summary</div>
          </td>
        </tr>

        <!-- Body -->
        <tr>
          <td style="padding:40px;">
            <table width="100%" cellpadding="0" cellspacing="0">

              <!-- Greeting -->
              <tr>
                <td style="padding:0 0 28px;">
                  <h1 style="margin:0 0 12px;font-size:22px;font-weight:800;color:#F1F5F9;line-height:1.3;">Hi ${firstName},</h1>
                  <p style="margin:0;font-size:15px;color:#CBD5E1;line-height:1.7;">
                    Here's your personal spending summary for <strong style="color:#F1F5F9;">${label}</strong>.
                  </p>
                </td>
              </tr>

              <!-- Stat cards — 3 side by side -->
              <tr>
                <td style="padding:0 0 28px;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <!-- Income -->
                      <td width="31%" align="center" style="background:#0D2B1E;border:1px solid #16A34A;border-radius:12px;padding:18px 8px;">
                        <div style="font-size:10px;font-weight:700;color:#4ADE80;letter-spacing:1px;text-transform:uppercase;margin-bottom:6px;">Income</div>
                        <div style="font-size:16px;font-weight:800;color:#4ADE80;">+${fmt(totalIncome)}</div>
                      </td>
                      <td width="3%"></td>
                      <!-- Expenses -->
                      <td width="31%" align="center" style="background:#2D1515;border:1px solid #DC2626;border-radius:12px;padding:18px 8px;">
                        <div style="font-size:10px;font-weight:700;color:#F87171;letter-spacing:1px;text-transform:uppercase;margin-bottom:6px;">Expenses</div>
                        <div style="font-size:16px;font-weight:800;color:#F87171;">-${fmt(totalExpenses)}</div>
                      </td>
                      <td width="3%"></td>
                      <!-- Net -->
                      <td width="31%" align="center" style="background:${netBg};border:1px solid ${netBorder};border-radius:12px;padding:18px 8px;">
                        <div style="font-size:10px;font-weight:700;color:${netColor};letter-spacing:1px;text-transform:uppercase;margin-bottom:6px;">Net</div>
                        <div style="font-size:16px;font-weight:800;color:${netColor};">${netFmt}</div>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>

              ${chartSection}

              ${topCategories.length > 0 ? `
              <!-- Top categories table -->
              <tr>
                <td style="padding:0 0 28px;">
                  <p style="margin:0 0 0;font-size:12px;font-weight:700;color:#64748B;letter-spacing:1px;text-transform:uppercase;margin-bottom:12px;">Top Categories</p>
                  <table width="100%" cellpadding="0" cellspacing="0" style="border-radius:8px;overflow:hidden;border:1px solid #334155;">
                    ${catRows}
                  </table>
                </td>
              </tr>` : ''}

              ${aiSection}

              <!-- CTA — deep link opens app on device -->
              <tr>
                <td style="padding:0 0 8px;" align="center">
                  <a href="com.jafa.setall.app:///"
                     style="display:inline-block;background-color:#14B8A6;color:#0F172A;font-weight:700;font-size:16px;padding:16px 40px;border-radius:12px;text-decoration:none;">
                    Open SetAll →
                  </a>
                </td>
              </tr>

            </table>
          </td>
        </tr>

        <!-- Footer — matches welcome email footer exactly -->
        <tr>
          <td style="padding:24px 40px;border-top:1px solid #334155;text-align:center;">
            <p style="margin:0;font-size:12px;color:#475569;line-height:1.6;">
              To stop receiving these emails, go to <strong style="color:#64748B;">Settings → Notifications</strong> in the SetAll app.
            </p>
            <p style="margin:8px 0 0;font-size:12px;color:#475569;">
              Sent to ${profile.email} · <a href="${APP_URL}" style="color:#475569;text-decoration:underline;">setall.app</a>
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`
}
