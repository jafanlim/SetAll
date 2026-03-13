// Supabase Edge Function: notify a user by email that they were added to a group.
// Deploy: supabase functions deploy notify-group-invite
// Requires: RESEND_API_KEY secret set in Supabase project settings.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_ADDRESS   = 'noreply@setall.app'
const APP_URL        = 'https://setall.app'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin':  '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'authorization, content-type',
      },
    })
  }

  try {
    const { email, groupId, groupName } = await req.json() as {
      email?: string
      groupId?: string
      groupName?: string
    }

    if (!email || !email.includes('@')) {
      return new Response(JSON.stringify({ error: 'email required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    if (!RESEND_API_KEY) {
      console.warn('RESEND_API_KEY not set — skipping email delivery')
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const displayName = groupName || groupId || 'a group'

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        from:    `SetAll <${FROM_ADDRESS}>`,
        to:      [email],
        subject: `You've been added to "${displayName}" on SetAll`,
        html: `
          <div style="background:#0F172A;color:#E8E8EC;font-family:system-ui,sans-serif;padding:40px;border-radius:12px;max-width:480px;margin:0 auto;">
            <h1 style="font-size:28px;font-weight:800;margin-bottom:4px;">⚖️ SetAll</h1>
            <p style="color:#94A3B8;font-size:13px;margin-top:0 margin-bottom:32px;">Premium expense sharing</p>
            <hr style="border:none;border-top:1px solid #1E293B;margin:24px 0;" />
            <h2 style="font-size:20px;color:#14B8A6;">You've been added to a group</h2>
            <p style="font-size:14px;line-height:1.7;color:#CBD5E1;">
              You've been added to <strong style="color:#fff;">${displayName}</strong>.<br />
              Open SetAll to see your group expenses and balances.
            </p>
            <a href="${APP_URL}"
               style="display:inline-block;margin-top:24px;background:#14B8A6;color:#0F172A;font-weight:700;font-size:14px;padding:12px 28px;border-radius:8px;text-decoration:none;">
              Open SetAll
            </a>
            <p style="font-size:11px;color:#475569;margin-top:32px;">
              Sent to ${email} · <a href="${APP_URL}" style="color:#475569;">setall.app</a>
            </p>
          </div>
        `,
      }),
    })

    const data = await res.json()

    if (!res.ok) {
      console.error('Resend error:', data)
      return new Response(JSON.stringify({ error: data?.message ?? 'Resend API error' }), {
        status: res.status,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ ok: true, id: data.id }), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    })
  } catch (err) {
    console.error('Unexpected error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
