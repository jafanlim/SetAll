// Supabase Edge Function: send monthly spending digest emails.
// Scheduled via pg_cron: 0 9 1 * * (1st of each month, 09:00 UTC)
// Deploy: supabase functions deploy monthly-digest
// Requires secrets: RESEND_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

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

    // Previous calendar month window
    const now   = new Date()
    const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1))
    const end   = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))
    const label = monthName(start)

    // Fetch profiles that opted in
    const { data: profiles, error: profErr } = await admin
      .from('profiles')
      .select('id, name, notification_preferences')
      .filter('notification_preferences->>monthly_digest', 'eq', 'true')

    if (profErr) throw profErr
    if (!profiles || profiles.length === 0) {
      return new Response(JSON.stringify({ sent: 0 }), {
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Fetch user emails from auth.users (service role only)
    const { data: authUsers } = await admin.auth.admin.listUsers()
    const emailMap: Record<string, string> = {}
    for (const u of authUsers?.users ?? []) {
      if (u.email) emailMap[u.id] = u.email
    }

    let sent = 0

    for (const profile of profiles) {
      const uid   = profile.id as string
      const name  = (profile.name as string | null) ?? 'there'
      const email = emailMap[uid]
      if (!email) continue

      // Wallet stats for prev month
      const { data: incomeRows } = await admin
        .from('wallet_entries')
        .select('amount, currency')
        .eq('user_id', uid)
        .eq('is_income', true)
        .eq('is_deleted', false)
        .gte('created_at', start.toISOString())
        .lt('created_at', end.toISOString())

      const { data: expenseRows } = await admin
        .from('wallet_entries')
        .select('amount, category, currency')
        .eq('user_id', uid)
        .eq('is_income', false)
        .eq('is_deleted', false)
        .gte('created_at', start.toISOString())
        .lt('created_at', end.toISOString())

      const totalIncome   = (incomeRows  ?? []).reduce((s, r) => s + (parseFloat(r.amount) || 0), 0)
      const totalExpenses = (expenseRows ?? []).reduce((s, r) => s + (parseFloat(r.amount) || 0), 0)
      const net           = totalIncome - totalExpenses
      const currency      = incomeRows?.[0]?.currency ?? expenseRows?.[0]?.currency ?? 'USD'

      // Top category
      const catTotals: Record<string, number> = {}
      for (const r of expenseRows ?? []) {
        const cat = (r.category as string) || 'Other'
        catTotals[cat] = (catTotals[cat] ?? 0) + (parseFloat(r.amount) || 0)
      }
      const topCategory = Object.entries(catTotals).sort((a, b) => b[1] - a[1])[0]
      const topCatName  = topCategory?.[0] ?? '—'
      const topCatAmt   = topCategory?.[1]?.toFixed(2) ?? '0.00'

      const fmt = (v: number) => `${currency} ${Math.abs(v).toFixed(2)}`

      const html = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F8FAFC;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#F8FAFC;padding:40px 0">
    <tr><td align="center">
      <table width="520" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,.08)">
        <!-- Header -->
        <tr><td style="background:#0F172A;padding:28px 32px">
          <p style="margin:0;color:#14B8A6;font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase">SetAll</p>
          <h1 style="margin:8px 0 0;color:#fff;font-size:22px;font-weight:800">Your ${label} Summary</h1>
        </td></tr>
        <!-- Body -->
        <tr><td style="padding:32px">
          <p style="margin:0 0 24px;font-size:15px;color:#1E293B">Hi ${name},</p>
          <p style="margin:0 0 24px;font-size:14px;color:#64748B;line-height:1.6">
            Here's your spending summary for <strong>${label}</strong>.
          </p>

          <!-- Stats row -->
          <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px">
            <tr>
              <td width="33%" align="center" style="background:#F0FDF4;border-radius:12px;padding:16px 8px">
                <p style="margin:0;font-size:11px;color:#16A34A;font-weight:600;text-transform:uppercase;letter-spacing:.5px">Income</p>
                <p style="margin:4px 0 0;font-size:18px;font-weight:800;color:#15803D">${fmt(totalIncome)}</p>
              </td>
              <td width="4%"></td>
              <td width="33%" align="center" style="background:#FFF1F2;border-radius:12px;padding:16px 8px">
                <p style="margin:0;font-size:11px;color:#E11D48;font-weight:600;text-transform:uppercase;letter-spacing:.5px">Expenses</p>
                <p style="margin:4px 0 0;font-size:18px;font-weight:800;color:#BE123C">${fmt(totalExpenses)}</p>
              </td>
              <td width="4%"></td>
              <td width="26%" align="center" style="background:${net >= 0 ? '#F0FDFA' : '#FFF1F2'};border-radius:12px;padding:16px 8px">
                <p style="margin:0;font-size:11px;color:${net >= 0 ? '#0D9488' : '#E11D48'};font-weight:600;text-transform:uppercase;letter-spacing:.5px">Net</p>
                <p style="margin:4px 0 0;font-size:18px;font-weight:800;color:${net >= 0 ? '#0F766E' : '#BE123C'}">${net >= 0 ? '+' : '-'}${fmt(net)}</p>
              </td>
            </tr>
          </table>

          <!-- Top category -->
          ${topCategory ? `<div style="background:#F8FAFC;border-radius:12px;padding:14px 18px;margin-bottom:24px">
            <span style="font-size:12px;color:#64748B">Top spending category: </span>
            <strong style="font-size:13px;color:#0F172A">${topCatName}</strong>
            <span style="font-size:13px;color:#64748B"> — ${currency} ${topCatAmt}</span>
          </div>` : ''}

          <!-- CTA -->
          <div align="center" style="margin-bottom:24px">
            <a href="${APP_URL}" style="display:inline-block;background:#14B8A6;color:#000;font-size:14px;font-weight:700;padding:13px 32px;border-radius:10px;text-decoration:none">
              Open SetAll ↗
            </a>
          </div>

          <hr style="border:none;border-top:1px solid #E2E8F0;margin-bottom:20px">
          <p style="margin:0;font-size:11px;color:#94A3B8;text-align:center">
            To stop receiving these emails, go to <strong>Settings → Notifications</strong> in the SetAll app.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`

      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${RESEND_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from:    FROM_ADDRESS,
          to:      [email],
          subject: `Your SetAll summary for ${label}`,
          html,
        }),
      })

      if (res.ok) sent++
    }

    return new Response(JSON.stringify({ sent, total: profiles.length }), {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  }
})
