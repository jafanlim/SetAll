/**
 * SetAll — send-email Auth Hook
 * ─────────────────────────────────────────────────────────────────────────────
 * Supabase calls this Edge Function instead of its built-in SMTP whenever it
 * needs to send an auth email. Wire it up in:
 *   Dashboard → Authentication → Hooks → "Send Email" hook
 *
 * Supported email types (from Supabase hook payload `email_data.email_action_type`):
 *   signup              — email address confirmation after registration
 *   recovery            — password reset
 *   magiclink           — magic link sign-in
 *   email_change_new    — confirm new email address
 *   email_change_current— notify old email address of change
 *
 * Secrets required (set via CLI):
 *   supabase secrets set RESEND_API_KEY="re_xxxxxxxxxxxx"
 *
 * Deploy:
 *   supabase functions deploy send-email --no-verify-jwt
 *
 * Note: --no-verify-jwt is required because Supabase's hook system calls this
 * function with its own internal auth, not a user JWT.
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const RESEND_API_KEY    = Deno.env.get('RESEND_API_KEY') ?? ''
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const FROM_ADDRESS      = 'SetAll <noreply@setall.app>'
const APP_URL           = 'https://setall.app'

// ── Shared email shell ────────────────────────────────────────────────────────

function emailShell(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${title}</title>
</head>
<body style="margin:0;padding:0;background:#0F172A;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#0F172A;padding:48px 16px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#1E293B;border:1px solid #334155;border-radius:16px;overflow:hidden;">

        <!-- Header -->
        <tr>
          <td style="background:linear-gradient(135deg,#0F172A 0%,#1a2744 100%);padding:40px 40px 32px;text-align:center;border-bottom:1px solid #334155;">
            <div style="font-size:36px;margin-bottom:8px;">⚖️</div>
            <div style="font-size:24px;font-weight:800;color:#F1F5F9;letter-spacing:-0.5px;">SetAll</div>
            <div style="font-size:12px;color:#64748B;margin-top:4px;letter-spacing:0.5px;text-transform:uppercase;">Premium Expense Sharing</div>
          </td>
        </tr>

        ${body}

        <!-- Footer -->
        <tr>
          <td style="padding:24px 40px;border-top:1px solid #334155;text-align:center;">
            <p style="margin:0;font-size:12px;color:#475569;line-height:1.6;">
              <a href="${APP_URL}" style="color:#475569;text-decoration:underline;">setall.app</a>
              &nbsp;·&nbsp;
              <a href="${APP_URL}/privacy" style="color:#475569;text-decoration:underline;">Privacy Policy</a>
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`
}

function ctaButton(label: string, url: string): string {
  return `<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:32px;">
    <tr>
      <td align="center">
        <a href="${url}"
           style="display:inline-block;background:#14B8A6;color:#0F172A;font-weight:700;font-size:15px;padding:14px 36px;border-radius:10px;text-decoration:none;letter-spacing:-0.2px;">
          ${label}
        </a>
      </td>
    </tr>
  </table>`
}

function fallbackLink(url: string): string {
  return `<p style="margin:0;font-size:12px;color:#64748B;line-height:1.8;">
    Or copy and paste this URL into your browser:<br>
    <a href="${url}" style="color:#14B8A6;word-break:break-all;">${url}</a>
  </p>`
}

// ── Email builders ─────────────────────────────────────────────────────────────

function buildConfirmEmail(email: string, confirmUrl: string): string {
  const body = `
    <tr>
      <td style="padding:40px;">
        <h1 style="margin:0 0 16px;font-size:22px;font-weight:800;color:#F1F5F9;line-height:1.3;">
          Confirm your email address
        </h1>
        <p style="margin:0 0 8px;font-size:15px;color:#CBD5E1;line-height:1.7;">
          Almost there! Click the button below to confirm
          <strong style="color:#F1F5F9;">${email}</strong>
          and activate your SetAll account.
        </p>
        <p style="margin:0 0 32px;font-size:13px;color:#64748B;">
          This link expires in 24 hours.
        </p>
        ${ctaButton('Confirm email address', confirmUrl)}
        ${fallbackLink(confirmUrl)}
      </td>
    </tr>`
  return emailShell('Confirm your SetAll email', body)
}

function buildRecoveryEmail(email: string, resetUrl: string): string {
  const body = `
    <tr>
      <td style="padding:40px;">
        <div style="width:56px;height:56px;background:#0F172A;border-radius:14px;border:1px solid #334155;text-align:center;margin-bottom:24px;line-height:56px;font-size:26px;">🔐</div>
        <h1 style="margin:0 0 16px;font-size:22px;font-weight:800;color:#F1F5F9;line-height:1.3;">
          Reset your password
        </h1>
        <p style="margin:0 0 8px;font-size:15px;color:#CBD5E1;line-height:1.7;">
          We received a request to reset the password for
          <strong style="color:#F1F5F9;">${email}</strong>.
        </p>
        <p style="margin:0 0 32px;font-size:13px;color:#64748B;">
          This link expires in 1 hour. If you didn't request this, you can safely ignore this email — your password won't change.
        </p>
        ${ctaButton('Reset password', resetUrl)}
        ${fallbackLink(resetUrl)}
      </td>
    </tr>
    <tr>
      <td style="padding:0 40px 32px;">
        <div style="background:#0F172A;border:1px solid #334155;border-radius:8px;padding:16px;">
          <p style="margin:0;font-size:12px;color:#64748B;line-height:1.6;">
            <strong style="color:#94A3B8;">Security tip:</strong> SetAll will never ask for your password via email or support chat.
            Contact us at <a href="mailto:support@setall.app" style="color:#14B8A6;text-decoration:none;">support@setall.app</a> if you're unsure.
          </p>
        </div>
      </td>
    </tr>`
  return emailShell('Reset your SetAll password', body)
}

function buildMagicLinkEmail(email: string, magicUrl: string): string {
  const body = `
    <tr>
      <td style="padding:40px;">
        <h1 style="margin:0 0 16px;font-size:22px;font-weight:800;color:#F1F5F9;line-height:1.3;">
          Your sign-in link
        </h1>
        <p style="margin:0 0 8px;font-size:15px;color:#CBD5E1;line-height:1.7;">
          Click the button below to sign in to SetAll as
          <strong style="color:#F1F5F9;">${email}</strong>.
        </p>
        <p style="margin:0 0 32px;font-size:13px;color:#64748B;">
          This link expires in 1 hour and can only be used once.
        </p>
        ${ctaButton('Sign in to SetAll', magicUrl)}
        ${fallbackLink(magicUrl)}
      </td>
    </tr>`
  return emailShell('Sign in to SetAll', body)
}

function buildEmailChangeEmail(email: string, changeUrl: string, isNew: boolean): string {
  const headline = isNew
    ? 'Confirm your new email address'
    : 'Your email address is being changed'
  const detail = isNew
    ? `Click below to confirm <strong style="color:#F1F5F9;">${email}</strong> as your new SetAll email address.`
    : `This is a notification that a request was made to change the email associated with your SetAll account. If this wasn't you, contact support immediately.`
  const body = `
    <tr>
      <td style="padding:40px;">
        <h1 style="margin:0 0 16px;font-size:22px;font-weight:800;color:#F1F5F9;line-height:1.3;">
          ${headline}
        </h1>
        <p style="margin:0 0 32px;font-size:15px;color:#CBD5E1;line-height:1.7;">
          ${detail}
        </p>
        ${isNew ? ctaButton('Confirm new email', changeUrl) : ''}
        ${isNew ? fallbackLink(changeUrl) : `<p style="font-size:13px;color:#64748B;">If you did request this change, no action is needed on this address.</p>`}
      </td>
    </tr>`
  return emailShell(headline, body)
}

// ── Subject lines ──────────────────────────────────────────────────────────────

function subjectFor(actionType: string): string {
  switch (actionType) {
    case 'signup':              return 'Confirm your SetAll email address'
    case 'recovery':            return 'Reset your SetAll password'
    case 'magiclink':           return 'Your SetAll sign-in link'
    case 'email_change_new':    return 'Confirm your new SetAll email address'
    case 'email_change_current':return 'Your SetAll email address is being changed'
    default:                    return 'A message from SetAll'
  }
}

// ── Main handler ───────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin':  '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'content-type, authorization',
      },
    })
  }

  try {
    const payload = await req.json()

    // Log full payload so we can inspect it in Dashboard → Edge Function logs
    console.log('send-email hook payload:', JSON.stringify(payload))

    // Supabase Auth Hook payload shape:
    // { user: { email }, email_data: { email_action_type, token, token_hash, redirect_to, site_url } }
    const user       = payload?.user       ?? {}
    const emailData  = payload?.email_data ?? {}

    const toEmail    = user.email as string | undefined
    const actionType = emailData.email_action_type as string | undefined
    const tokenHash  = emailData.token_hash as string | undefined
    const redirectTo = emailData.redirect_to as string | undefined
    const siteUrl    = emailData.site_url   as string | undefined ?? APP_URL

    // Also try the 'token' field as fallback (OTP flow)
    const token      = emailData.token as string | undefined

    console.log('send-email emailData:', JSON.stringify(emailData))
    console.log(`send-email: toEmail=${toEmail} actionType=${actionType} token_hash=${tokenHash} token=${token}`)
    // actionUrl logged below after construction

    if (!toEmail || !actionType) {
      console.error('send-email: missing required fields', { toEmail, actionType, payloadKeys: Object.keys(payload) })
      return new Response(JSON.stringify({ error: 'Missing user.email or email_action_type' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Build the confirmation URL.
    // token_hash must be URL-encoded (may contain base64 chars like +/=).
    // Fall back to OTP token if token_hash is absent.
    const SUPABASE_URL  = 'https://vrsmsgyxeyzyrdonsnrk.supabase.co'
    const finalRedirect = redirectTo ?? `${APP_URL}/login`
    let actionUrl: string
    if (tokenHash) {
      actionUrl = `${SUPABASE_URL}/auth/v1/verify?apikey=${SUPABASE_ANON_KEY}&token_hash=${encodeURIComponent(tokenHash)}&type=${encodeURIComponent(actionType)}&redirect_to=${encodeURIComponent(finalRedirect)}`
    } else if (token) {
      actionUrl = `${SUPABASE_URL}/auth/v1/verify?apikey=${SUPABASE_ANON_KEY}&token=${encodeURIComponent(token)}&type=${encodeURIComponent(actionType)}&redirect_to=${encodeURIComponent(finalRedirect)}`
    } else {
      console.error('send-email: no token or token_hash in payload', JSON.stringify(emailData))
      actionUrl = finalRedirect
    }

    console.log('send-email actionUrl:', actionUrl)

    // Select HTML template
    let html: string
    switch (actionType) {
      case 'signup':
        html = buildConfirmEmail(toEmail, actionUrl)
        break
      case 'recovery':
        html = buildRecoveryEmail(toEmail, actionUrl)
        break
      case 'magiclink':
        html = buildMagicLinkEmail(toEmail, actionUrl)
        break
      case 'email_change_new':
        html = buildEmailChangeEmail(toEmail, actionUrl, true)
        break
      case 'email_change_current':
        html = buildEmailChangeEmail(toEmail, actionUrl, false)
        break
      default:
        // Unknown type — use a generic confirmation layout
        html = buildConfirmEmail(toEmail, actionUrl)
    }

    if (!RESEND_API_KEY) {
      console.warn(`RESEND_API_KEY not set — skipping ${actionType} email to ${toEmail}`)
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const res = await fetch('https://api.resend.com/emails', {
      method:  'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        from:    FROM_ADDRESS,
        to:      [toEmail],
        subject: subjectFor(actionType),
        html,
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

    console.log(`✓ ${actionType} email sent to ${toEmail} (id: ${data.id})`)
    return new Response(JSON.stringify({ ok: true, id: data.id }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error('Unexpected error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
