// SetAll — bug-triage Edge Function  (FEAT-P46)
// Triggered by Postgres trigger on INSERT into public.bug_reports.
// 1. Calls Groq llama-3.3-70b-versatile to triage the report.
// 2. Updates bug_reports row with triage results.
// 3. Sends a formatted email to contact@setall.app via Resend.
//
// Secrets required (all already set):
//   GROQ_API_KEY, RESEND_API_KEY, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy: supabase functions deploy bug-triage --no-verify-jwt

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const GROQ_API_KEY  = Deno.env.get('GROQ_API_KEY')              ?? ''
const GROQ_MODEL    = 'llama-3.3-70b-versatile'
const GROQ_URL      = 'https://api.groq.com/openai/v1/chat/completions'
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')           ?? ''
const SUPABASE_URL  = Deno.env.get('SUPABASE_URL')              ?? ''
const SERVICE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const CORS_HEADERS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  try {
    // Parse webhook body from Postgres trigger (row_to_json(NEW))
    const row = await req.json() as {
      id:          string
      description: string
      app_version: string | null
      device_info: string | null
      severity:    string | null
      user_id:     string | null
    }

    const { id, description, app_version, device_info, severity } = row
    if (!id || !description) {
      return new Response(JSON.stringify({ error: 'missing id or description' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const admin = createClient(SUPABASE_URL, SERVICE_KEY)

    // ── 1. Call Groq ─────────────────────────────────────────────────────────
    const systemPrompt =
      `You are a mobile app bug triage assistant for SetAll, a Flutter personal finance app (iOS/Android/macOS/Windows). ` +
      `Stack: Flutter 3.x, Riverpod 2.x, Supabase (Postgres + realtime + edge functions), SQLite local-first sync, Firebase FCM, iOS WidgetKit. ` +
      `Given a bug report, respond ONLY with valid JSON:\n` +
      `{\n` +
      `  "triage_summary": "1-2 sentence root cause hypothesis",\n` +
      `  "severity": "critical|high|medium|low|info",\n` +
      `  "affected_area": "wallet|sync|widget|auth|groups|ai|export|notifications|ui|other",\n` +
      `  "cascade_prompt": "A Cascade/Windsurf prompt starting with ## MANDATORY PRINCIPLE: ACT that tells the AI to (1) read relevant files for the affected area, (2) reproduce the described behaviour, (3) fix it, (4) run flutter analyze + flutter test, (5) commit. Max 600 chars."\n` +
      `}`

    const userMessage =
      `Bug: ${description}. Version: ${app_version ?? 'unknown'}. Device: ${device_info ?? 'unknown'}.`

    const groqRes = await fetch(GROQ_URL, {
      method: 'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': `Bearer ${GROQ_API_KEY}`,
      },
      body: JSON.stringify({
        model:       GROQ_MODEL,
        temperature: 0.3,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user',   content: userMessage  },
        ],
      }),
    })

    let triage: {
      triage_summary: string
      severity:       string
      affected_area:  string
      cascade_prompt: string
    } = {
      triage_summary: 'Triage unavailable — Groq did not return a parseable response.',
      severity:       severity ?? 'medium',
      affected_area:  'other',
      cascade_prompt: '',
    }

    try {
      const groqJson = await groqRes.json()
      const text     = groqJson?.choices?.[0]?.message?.content ?? '{}'
      // Strip potential markdown fences Groq may wrap JSON in
      const cleaned  = text.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim()
      const parsed   = JSON.parse(cleaned)
      triage = {
        triage_summary: parsed.triage_summary ?? triage.triage_summary,
        severity:       parsed.severity       ?? triage.severity,
        affected_area:  parsed.affected_area  ?? triage.affected_area,
        cascade_prompt: parsed.cascade_prompt ?? triage.cascade_prompt,
      }
    } catch (_) { /* keep defaults */ }

    // ── 2. Update bug_reports row ─────────────────────────────────────────────
    await admin.from('bug_reports').update({
      triage_summary:  triage.triage_summary,
      triage_severity: triage.severity,
      triage_area:     triage.affected_area,
      cascade_prompt:  triage.cascade_prompt,
      triage_model:    GROQ_MODEL,
      triaged_at:      new Date().toISOString(),
    }).eq('id', id)

    // ── 3. Send email to contact@setall.app via Resend ────────────────────────
    const descPreview  = description.slice(0, 60)
    const emailSubject = `[SetAll Bug] ${triage.severity} — ${triage.affected_area}: ${descPreview}`

    const emailHtml = `
<h2>Bug Report</h2>
<p><b>Version:</b> ${app_version ?? '—'} | <b>Device:</b> ${device_info ?? '—'}</p>
<h3>Description</h3>
<p>${description}</p>
<h3>AI Triage</h3>
<p><b>Severity:</b> ${triage.severity} | <b>Area:</b> ${triage.affected_area}</p>
<p>${triage.triage_summary}</p>
<h3>Cascade Fix Prompt — paste directly into Windsurf</h3>
<pre style="background:#f5f5f5;padding:12px;border-radius:6px;font-size:13px;white-space:pre-wrap">${triage.cascade_prompt}</pre>
<p><a href="https://supabase.com/dashboard/project/vrsmsgyxeyzyrdonsnrk/editor?table=bug_reports">View all reports →</a></p>
`

    if (RESEND_API_KEY) {
      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${RESEND_API_KEY}`,
          'Content-Type':  'application/json',
        },
        body: JSON.stringify({
          from:    'noreply@setall.app',
          to:      ['contact@setall.app'],
          subject: emailSubject,
          html:    emailHtml,
        }),
      })
    }

    return new Response(JSON.stringify({ triaged: true }), {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status:  500,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    })
  }
})
