import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_ADDRESS   = 'noreply@setall.app'

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
    const { to } = await req.json() as { to?: string }
    if (!to || !to.includes('@')) {
      return new Response(JSON.stringify({ error: 'Invalid or missing "to" address' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    if (!RESEND_API_KEY) {
      return new Response(
        JSON.stringify({ error: 'RESEND_API_KEY secret not configured in Supabase' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } },
      )
    }

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        from:    `SetAll <${FROM_ADDRESS}>`,
        to:      [to],
        subject: '[SetAll] Test email — delivery confirmed ✓',
        html: `
          <div style="background:#0F172A;color:#E8E8EC;font-family:system-ui,sans-serif;padding:40px;border-radius:12px;max-width:480px;margin:0 auto;">
            <h1 style="font-size:28px;font-weight:800;margin-bottom:8px;">⚖️ SetAll</h1>
            <p style="color:#94A3B8;font-size:14px;margin-top:0;">noreply@setall.app</p>
            <hr style="border:none;border-top:1px solid #1E293B;margin:24px 0;" />
            <h2 style="font-size:20px;color:#14B8A6;">Email delivery confirmed ✓</h2>
            <p style="font-size:14px;line-height:1.7;color:#CBD5E1;">
              This is a test email sent from the SetAll Developer Settings panel.<br />
              If you received this, your <strong>Resend + Cloudflare DNS</strong> setup is working correctly.
            </p>
            <p style="font-size:12px;color:#475569;margin-top:32px;">
              Sent to: ${to}<br />
              From: ${FROM_ADDRESS}<br />
              Time: ${new Date().toISOString()}
            </p>
          </div>
        `,
      }),
    })

    const data = await res.json()

    if (!res.ok) {
      return new Response(JSON.stringify({ error: data?.message ?? 'Resend API error' }), {
        status: res.status,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ id: data.id, to }), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
