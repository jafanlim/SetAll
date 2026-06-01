// Supabase Edge Function: send a welcome email when a user confirms their email.
// Triggered by a Postgres trigger on auth.users (see migration 20260314000000).
// Deploy: supabase functions deploy send-welcome-email
// Requires secrets:
//   RESEND_API_KEY       — Resend API key
//   WELCOME_HOOK_SECRET  — Shared secret set in both this function and the DB trigger
//
// ── AUTH MODEL (OPEN-3) ────────────────────────────────────────────────────────
// DO NOT add an x-edge-secret guard to this function.
// This function is called by a Supabase Auth trigger (on_profile_created), which
// sends its own webhook secret in the x-webhook-secret header (WELCOME_HOOK_SECRET).
// The x-edge-secret pattern is for DB trigger / cron functions only. Replacing or
// supplementing WELCOME_HOOK_SECRET with x-edge-secret would break the welcome email
// flow because the Auth trigger sends x-webhook-secret, not x-edge-secret.
// See docs/setall-supabase-key-migration.md §"send-welcome-email" for the exception rationale.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const RESEND_API_KEY      = Deno.env.get('RESEND_API_KEY')      ?? ''
const WELCOME_HOOK_SECRET = Deno.env.get('WELCOME_HOOK_SECRET') ?? ''
const FROM_ADDRESS        = 'noreply@setall.app'
const APP_URL             = 'https://setall.app'

const WELCOME_SUBJECT: Record<string, string> = {
  en: 'Welcome to SetAll — stop doing math ⚖️',
  ru: 'Добро пожаловать в SetAll — бросьте считать в уме ⚖️',
  de: 'Willkommen bei SetAll — nie wieder kopfrechnen ⚖️',
  es: 'Bienvenido a SetAll — deja de hacer cálculos ⚖️',
  fr: 'Bienvenue sur SetAll — fini les calculs mentaux ⚖️',
  ka: 'კეთილი დაბრევით SetAll-ში — აღარ გატარიი არითმეტიკა ⚖️',
}

type WelcomeStrings = {
  heading: string
  body: string
  cta: string
}

const WELCOME_COPY: Record<string, WelcomeStrings> = {
  en: {
    heading: 'Welcome — your account is ready 🎉',
    body:    "Your email has been confirmed. You're all set to split expenses, simplify debts, and settle with friends across any currency — without the mental math.",
    cta:     'Open SetAll →',
  },
  ru: {
    heading: 'Добро пожаловать — ваш аккаунт готов 🎉',
    body:    'Ваш email подтверждён. Теперь можно делить расходы, упрощать долги и рассчитываться с друзьями в любой валюте — без мысленных вычислений.',
    cta:     'Открыть SetAll →',
  },
  de: {
    heading: 'Willkommen — Ihr Konto ist bereit 🎉',
    body:    'Ihre E-Mail wurde bestätigt. Teilen Sie Ausgaben auf, vereinfachen Sie Schulden und rechnen Sie mit Freunden in jeder Währung ab — ganz ohne Kopfrechnen.',
    cta:     'SetAll öffnen →',
  },
  es: {
    heading: 'Bienvenido — tu cuenta está lista 🎉',
    body:    'Tu email ha sido confirmado. Ya puedes dividir gastos, simplificar deudas y saldar cuentas con amigos en cualquier moneda — sin cálculos mentales.',
    cta:     'Abrir SetAll →',
  },
  fr: {
    heading: 'Bienvenue — votre compte est prêt 🎉',
    body:    'Votre email a été confirmé. Vous pouvez désormais partager des dépenses, simplifier les dettes et solder les comptes avec vos amis dans n’importe quelle devise — sans calcul mental.',
    cta:     'Ouvrir SetAll →',
  },
  ka: {
    heading: 'კეთილი დაბრევით — თქვენი ანგარიში მზადაა 🎉',
    body:    'თქვენი ელ-ფოსტი დადასტურდა. ახლა შეგიძლიათ გადახარდოთ განაწილდოთ და მეგობრებთან გაანგარიშოთ ნებისმიერ ვალუტაში — შინაგან გარეშების გარეშე.',
    cta:     'SetAll-ის გახსნა →',
  },
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type, x-webhook-secret',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  // Verify internal webhook secret so only our DB trigger can call this.
  const incomingSecret = req.headers.get('x-webhook-secret') ?? ''
  if (WELCOME_HOOK_SECRET && incomingSecret !== WELCOME_HOOK_SECRET) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  try {
    const { email, language_code } = await req.json() as { email?: string; userId?: string; language_code?: string }
    const lang = language_code ?? 'en'

    if (!email || !email.includes('@')) {
      return new Response(JSON.stringify({ error: 'email required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    if (!RESEND_API_KEY) {
      console.warn('RESEND_API_KEY not set — skipping welcome email')
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        from:    `SetAll <${FROM_ADDRESS}>`,
        to:      [email],
        subject: WELCOME_SUBJECT[lang] ?? WELCOME_SUBJECT['en'],
        html:    buildWelcomeHtml(email, lang),
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
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  } catch (err) {
    console.error('Unexpected error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})

function buildWelcomeHtml(email: string, lang = 'en'): string {
  const copy = WELCOME_COPY[lang] ?? WELCOME_COPY['en']
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Welcome to SetAll</title>
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

        <!-- Body -->
        <tr>
          <td style="padding:40px;">
            <h1 style="margin:0 0 16px;font-size:22px;font-weight:800;color:#F1F5F9;line-height:1.3;">
              ${copy.heading}
            </h1>
            <p style="margin:0 0 24px;font-size:15px;color:#CBD5E1;line-height:1.7;">
              ${copy.body}
            </p>

            <!-- Feature pills -->
            <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:32px;">
              <tr>
                <td style="padding:12px 16px;background:#0F172A;border-radius:8px;border:1px solid #1E293B;margin-bottom:8px;">
                  <span style="color:#14B8A6;font-size:14px;font-weight:600;">⚡ Greedy Flow engine</span>
                  <span style="color:#94A3B8;font-size:13px;"> — minimises the number of transfers in any group</span>
                </td>
              </tr>
              <tr><td style="height:8px;"></td></tr>
              <tr>
                <td style="padding:12px 16px;background:#0F172A;border-radius:8px;border:1px solid #1E293B;">
                  <span style="color:#F97316;font-size:14px;font-weight:600;">🌍 True multi-currency</span>
                  <span style="color:#94A3B8;font-size:13px;"> — USD, EUR, GEL, TRY and more, live rates</span>
                </td>
              </tr>
              <tr><td style="height:8px;"></td></tr>
              <tr>
                <td style="padding:12px 16px;background:#0F172A;border-radius:8px;border:1px solid #1E293B;">
                  <span style="color:#818CF8;font-size:14px;font-weight:600;">🎲 Bill Roulette</span>
                  <span style="color:#94A3B8;font-size:13px;"> — randomly pick who pays, split stays fair</span>
                </td>
              </tr>
            </table>

            <!-- CTA -->
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td align="center">
                  <a href="${APP_URL}/login"
                     style="display:inline-block;background:#14B8A6;color:#0F172A;font-weight:700;font-size:15px;padding:14px 36px;border-radius:10px;text-decoration:none;letter-spacing:-0.2px;">
                    ${copy.cta}
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
