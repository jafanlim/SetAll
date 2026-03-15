/**
 * SetAll — send-email Auth Hook
 * ─────────────────────────────────────────────────────────────────────────────
 * Supabase calls this Edge Function instead of its built-in SMTP whenever it
 * needs to send an auth email. Wire it up in:
 *   Dashboard → Authentication → Hooks → "Send Email" hook
 *
 * PKCE flow (default for Flutter SDK):
 *   token_hash starts with "pkce_" → link points to the APP (?code=<hash>)
 *   The Flutter SDK exchanges the code via getSessionFromUrl() on load.
 *   Non-PKCE token_hash → standard /auth/v1/verify endpoint.
 *
 * Secrets required:
 *   supabase secrets set RESEND_API_KEY="re_xxxxxxxxxxxx"
 *
 * Deploy:
 *   supabase functions deploy send-email --no-verify-jwt
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_ADDRESS   = 'SetAll App <noreply@setall.app>'
const APP_URL        = 'https://setall.app'
const SUPABASE_URL   = 'https://vrsmsgyxeyzyrdonsnrk.supabase.co'

// ── Pro email shell (Polycam / Apple style — pure black) ──────────────────────

function emailShell(title: string, preheader: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${title}</title>
</head>
<body style="margin:0;padding:0;background:#000000;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <!-- Preheader (hidden preview text) -->
  <div style="display:none;max-height:0;overflow:hidden;">${preheader}&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>

  <table width="100%" cellpadding="0" cellspacing="0" style="background:#000000;padding:40px 16px 24px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:540px;">

        <!-- Logo bar -->
        <tr>
          <td style="padding:0 0 32px;text-align:center;">
            <span style="font-size:20px;font-weight:800;color:#FFFFFF;letter-spacing:-0.5px;">SetAll</span>
          </td>
        </tr>

        <!-- Card -->
        <tr>
          <td style="background:#111111;border-radius:0;overflow:hidden;">
            ${body}
          </td>
        </tr>

        <!-- Footer -->
        <tr>
          <td style="padding:28px 0 0;text-align:center;">
            <p style="margin:0 0 6px;font-size:11px;color:#3D3D3D;line-height:1.7;">
              SetAll App · Dubai, UAE
            </p>
            <p style="margin:0;font-size:11px;color:#3D3D3D;line-height:1.7;">
              <a href="${APP_URL}" style="color:#3D3D3D;text-decoration:underline;">setall.app</a>
              &nbsp;&middot;&nbsp;
              <a href="${APP_URL}/privacy" style="color:#3D3D3D;text-decoration:underline;">Privacy</a>
              &nbsp;&middot;&nbsp;
              <a href="mailto:support@setall.app" style="color:#3D3D3D;text-decoration:underline;">Support</a>
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
  return `<table width="100%" cellpadding="0" cellspacing="0" style="margin:32px 0 8px;">
    <tr>
      <td align="center">
        <a href="${url}"
           style="display:inline-block;background:#FFFFFF;color:#000000;font-weight:700;font-size:15px;padding:15px 40px;border-radius:0;text-decoration:none;letter-spacing:-0.1px;min-width:200px;text-align:center;">
          ${label}
        </a>
      </td>
    </tr>
  </table>`
}

function fallbackLink(url: string): string {
  return `<p style="margin:24px 0 0;font-size:11px;color:#555555;line-height:1.8;">
    Or copy this link into your browser:<br>
    <a href="${url}" style="color:#888888;word-break:break-all;">${url}</a>
  </p>`
}

// ── Email builders ─────────────────────────────────────────────────────────────

function buildConfirmEmail(email: string, confirmUrl: string): string {
  const body = `
    <tr>
      <td style="padding:48px 40px 40px;">
        <p style="margin:0 0 4px;font-size:11px;font-weight:600;color:#555555;letter-spacing:1.5px;text-transform:uppercase;">Account confirmation</p>
        <h1 style="margin:0 0 20px;font-size:28px;font-weight:800;color:#FFFFFF;line-height:1.2;letter-spacing:-0.5px;">
          Confirm your email
        </h1>
        <p style="margin:0 0 6px;font-size:15px;color:#999999;line-height:1.7;">
          You're one step away. Tap the button to verify
        </p>
        <p style="margin:0 0 0;font-size:15px;color:#FFFFFF;font-weight:600;line-height:1.7;">
          ${email}
        </p>
        ${ctaButton('Confirm Email Address', confirmUrl)}
        <p style="margin:20px 0 0;font-size:12px;color:#555555;">Link expires in 24 hours.</p>
        ${fallbackLink(confirmUrl)}
      </td>
    </tr>`
  return emailShell('Confirm your SetAll email', 'Tap to verify your email address and activate your account.', body)
}

function buildRecoveryEmail(email: string, resetUrl: string): string {
  const body = `
    <tr>
      <td style="padding:48px 40px 40px;">
        <p style="margin:0 0 4px;font-size:11px;font-weight:600;color:#555555;letter-spacing:1.5px;text-transform:uppercase;">Security</p>
        <h1 style="margin:0 0 20px;font-size:28px;font-weight:800;color:#FFFFFF;line-height:1.2;letter-spacing:-0.5px;">
          Reset your password
        </h1>
        <p style="margin:0 0 6px;font-size:15px;color:#999999;line-height:1.7;">
          We received a reset request for
        </p>
        <p style="margin:0 0 0;font-size:15px;color:#FFFFFF;font-weight:600;line-height:1.7;">
          ${email}
        </p>
        ${ctaButton('Reset Password', resetUrl)}
        <p style="margin:20px 0 0;font-size:12px;color:#555555;">Expires in 1 hour. If you didn't request this, ignore this email — your password won't change.</p>
        ${fallbackLink(resetUrl)}
      </td>
    </tr>
    <tr>
      <td style="padding:0 40px 40px;">
        <div style="border-top:1px solid #1F1F1F;padding-top:20px;">
          <p style="margin:0;font-size:12px;color:#555555;line-height:1.6;">
            SetAll will never ask for your password by email. Contact
            <a href="mailto:support@setall.app" style="color:#888888;">support@setall.app</a> if concerned.
          </p>
        </div>
      </td>
    </tr>`
  return emailShell('Reset your SetAll password', 'A password reset was requested for your account.', body)
}

function buildMagicLinkEmail(email: string, magicUrl: string): string {
  const body = `
    <tr>
      <td style="padding:48px 40px 40px;">
        <p style="margin:0 0 4px;font-size:11px;font-weight:600;color:#555555;letter-spacing:1.5px;text-transform:uppercase;">Sign in</p>
        <h1 style="margin:0 0 20px;font-size:28px;font-weight:800;color:#FFFFFF;line-height:1.2;letter-spacing:-0.5px;">
          Your sign-in link
        </h1>
        <p style="margin:0 0 6px;font-size:15px;color:#999999;line-height:1.7;">
          Sign in as
        </p>
        <p style="margin:0 0 0;font-size:15px;color:#FFFFFF;font-weight:600;line-height:1.7;">
          ${email}
        </p>
        ${ctaButton('Sign In to SetAll', magicUrl)}
        <p style="margin:20px 0 0;font-size:12px;color:#555555;">This link expires in 1 hour and can only be used once.</p>
        ${fallbackLink(magicUrl)}
      </td>
    </tr>`
  return emailShell('Sign in to SetAll', 'Your one-tap sign-in link is ready.', body)
}

function buildEmailChangeEmail(email: string, changeUrl: string, isNew: boolean): string {
  const headline = isNew ? 'Confirm new email' : 'Email change notice'
  const sub      = isNew ? 'Email change' : 'Security notice'
  const detail   = isNew
    ? `Tap below to confirm your new address:`
    : `A request was made to change the email on your account. If this wasn't you, contact support immediately.`
  const body = `
    <tr>
      <td style="padding:48px 40px 40px;">
        <p style="margin:0 0 4px;font-size:11px;font-weight:600;color:#555555;letter-spacing:1.5px;text-transform:uppercase;">${sub}</p>
        <h1 style="margin:0 0 20px;font-size:28px;font-weight:800;color:#FFFFFF;line-height:1.2;letter-spacing:-0.5px;">
          ${headline}
        </h1>
        <p style="margin:0 0 6px;font-size:15px;color:#999999;line-height:1.7;">${detail}</p>
        ${isNew ? `<p style="margin:0 0 0;font-size:15px;color:#FFFFFF;font-weight:600;line-height:1.7;">${email}</p>` : ''}
        ${isNew ? ctaButton('Confirm New Email', changeUrl) : ''}
        ${isNew ? fallbackLink(changeUrl) : `<p style="margin:24px 0 0;font-size:12px;color:#555555;">If you requested this change, no action is needed.</p>`}
      </td>
    </tr>`
  return emailShell(headline, isNew ? 'Confirm your new email address.' : 'Your email address is being changed.', body)
}

// ── Subject lines ──────────────────────────────────────────────────────────────

function subjectFor(actionType: string): string {
  switch (actionType) {
    case 'signup':               return 'Confirm your SetAll email address'
    case 'recovery':             return 'Reset your SetAll password'
    case 'magiclink':            return 'Your SetAll sign-in link'
    case 'email_change_new':     return 'Confirm your new SetAll email'
    case 'email_change_current': return 'Your SetAll email is being changed'
    default:                     return 'A message from SetAll'
  }
}

// ── URL builder ────────────────────────────────────────────────────────────────
// PKCE tokens (pkce_ prefix) CANNOT be verified at /auth/v1/verify — GoTrue
// silently rejects them.  Instead, send the user to the app with ?code=<hash>;
// the Flutter SDK exchanges the code via getSessionFromUrl() on startup.

function buildActionUrl(tokenHash: string | undefined, token: string | undefined, actionType: string, finalRedirect: string): string {
  if (tokenHash) {
    if (tokenHash.startsWith('pkce_')) {
      const sep = finalRedirect.includes('?') ? '&' : '?'
      return `${finalRedirect}${sep}code=${encodeURIComponent(tokenHash)}&type=${encodeURIComponent(actionType)}`
    }
    return `${SUPABASE_URL}/auth/v1/verify?token_hash=${encodeURIComponent(tokenHash)}&type=${encodeURIComponent(actionType)}&redirect_to=${encodeURIComponent(finalRedirect)}`
  }
  if (token) {
    return `${SUPABASE_URL}/auth/v1/verify?token=${encodeURIComponent(token)}&type=${encodeURIComponent(actionType)}&redirect_to=${encodeURIComponent(finalRedirect)}`
  }
  return finalRedirect
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
    const payload    = await req.json()
    const user       = payload?.user       ?? {}
    const emailData  = payload?.email_data ?? {}

    const toEmail    = user.email   as string | undefined
    const actionType = emailData.email_action_type as string | undefined
    const tokenHash  = emailData.token_hash        as string | undefined
    const token      = emailData.token             as string | undefined
    const redirectTo = emailData.redirect_to       as string | undefined

    console.log(`send-email: type=${actionType} to=${toEmail} token_hash=${tokenHash} token=${token}`)

    if (!toEmail || !actionType) {
      console.error('send-email: missing required fields')
      return new Response(JSON.stringify({ error: 'Missing user.email or email_action_type' }), {
        status: 400, headers: { 'Content-Type': 'application/json' },
      })
    }

    const finalRedirect = redirectTo ?? `${APP_URL}/login`
    const actionUrl     = buildActionUrl(tokenHash, token, actionType, finalRedirect)
    console.log('send-email actionUrl:', actionUrl)

    let html: string
    switch (actionType) {
      case 'signup':               html = buildConfirmEmail(toEmail, actionUrl);              break
      case 'recovery':             html = buildRecoveryEmail(toEmail, actionUrl);             break
      case 'magiclink':            html = buildMagicLinkEmail(toEmail, actionUrl);            break
      case 'email_change_new':     html = buildEmailChangeEmail(toEmail, actionUrl, true);    break
      case 'email_change_current': html = buildEmailChangeEmail(toEmail, actionUrl, false);   break
      default:                     html = buildConfirmEmail(toEmail, actionUrl)
    }

    if (!RESEND_API_KEY) {
      console.warn(`RESEND_API_KEY not set — skipping ${actionType} email to ${toEmail}`)
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        status: 200, headers: { 'Content-Type': 'application/json' },
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
        headers: {
          'List-Unsubscribe': `<mailto:unsubscribe@setall.app?subject=unsubscribe>`,
          'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
        },
      }),
    })

    const data = await res.json()
    if (!res.ok) {
      console.error('Resend error:', data)
      return new Response(JSON.stringify({ error: data?.message ?? 'Resend API error' }), {
        status: res.status, headers: { 'Content-Type': 'application/json' },
      })
    }

    console.log(`✓ ${actionType} email sent to ${toEmail} (id: ${data.id})`)
    return new Response(JSON.stringify({ ok: true, id: data.id }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error('Unexpected error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }
})
