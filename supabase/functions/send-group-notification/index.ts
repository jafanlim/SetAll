/**
 * SetAll — send-group-notification Edge Function  (FEAT-20)
 * ──────────────────────────────────────────────────────────
 * Receives a list of recipient user IDs and sends FCM v1 push
 * notifications to all their registered devices.
 *
 * Secrets required:
 *   supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}'
 *
 * Deploy:
 *   supabase functions deploy send-group-notification
 *
 * Request body:
 *   {
 *     recipientUserIds: string[],
 *     title:  string,
 *     body:   string,
 *     data:   { route: string, groupId: string }
 *   }
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { create, getNumericDate } from 'https://deno.land/x/djwt@v3.0.2/mod.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')              ?? ''
const SERVICE_KEY  = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}')['default'] ?? ''
const SA_JSON      = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')  ?? '{}'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
}

// ── FCM v1 JWT helper ────────────────────────────────────────────────────────
async function getFcmAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss:   sa.client_email,
    sub:   sa.client_email,
    aud:   'https://oauth2.googleapis.com/token',
    iat:   now,
    exp:   now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }

  // Import RSA private key from PEM
  const pemBody = (sa.private_key as string)
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8', keyBytes.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  )

  const jwt = await create({ alg: 'RS256', typ: 'JWT' }, payload, cryptoKey)

  // Exchange JWT for access token
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })
  const tokenJson = await tokenRes.json()
  return tokenJson.access_token as string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

    // x-edge-secret gate (P1): only the DB trigger/cron (which sends this header
    // from Vault edge_shared_secret) may invoke this function. verify_jwt=false,
    // so this header check is the ONLY auth on the function body.
    const expected = Deno.env.get('EDGE_SHARED_SECRET') ?? ''
    const provided = req.headers.get('x-edge-secret') ?? ''
    if (expected.length === 0 || provided !== expected) {
      return new Response(JSON.stringify({ error: 'unauthorized' }), {
        status: 401,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      })
    }

  try {
    const { recipientUserIds, title, body, data } = await req.json() as {
      recipientUserIds: string[]
      title: string
      body:  string
      data:  Record<string, string>
    }

    if (!recipientUserIds?.length) {
      return new Response(JSON.stringify({ sent: 0, failed: 0 }), {
        headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
      })
    }

    const admin = createClient(SUPABASE_URL, SERVICE_KEY)

    // Fetch FCM tokens for all recipient users
    const { data: tokenRows } = await admin
      .from('fcm_tokens')
      .select('token')
      .in('user_id', recipientUserIds)

    const tokens = (tokenRows ?? []).map((r: any) => r.token as string).filter(Boolean)
    if (!tokens.length) {
      return new Response(JSON.stringify({ sent: 0, failed: 0 }), {
        headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
      })
    }

    // Parse service account and get access token
    const sa = JSON.parse(SA_JSON)
    const projectId = sa.project_id as string
    const accessToken = await getFcmAccessToken(sa)

    const FCM_URL = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

    let sent = 0, failed = 0
    for (const token of tokens) {
      const res = await fetch(FCM_URL, {
        method:  'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type':  'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data: Object.fromEntries(
              Object.entries(data ?? {}).map(([k, v]) => [k, String(v)])
            ),
          },
        }),
      })
      if (res.ok) { sent++ } else {
        failed++
        console.error(`FCM send failed for token ${token.slice(0, 20)}…: ${await res.text()}`)
      }
    }

    return new Response(JSON.stringify({ sent, failed }), {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status:  500,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  }
})
