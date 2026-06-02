// FEAT-13b: Migrated from Gemini API (suspended a.setall.app@gmail.com account)
// to Groq API (llama-3.3-70b-versatile). Same request/response shape.
// API key: process.env.GROQ_API_KEY (set in Netlify environment variables)
// CHORE-01: Active path for setall.app web portal ONLY.
// Flutter client uses supabase/functions/ai-analyst/index.ts directly.
// Keep both in sync when changing model, prompt, or response shape.
// SECURITY: Bearer token verified via supabase.auth.getUser; per-user rate limit 20/60s.

const { createClient } = require('@supabase/supabase-js');

const GROQ_API_URL     = 'https://api.groq.com/openai/v1/chat/completions';
const SUPABASE_URL     = process.env.SUPABASE_URL     || 'https://vrsmsgyxeyzyrdonsnrk.supabase.co';
const SUPABASE_ANON    = process.env.SUPABASE_ANON_KEY || '';
const RATE_LIMIT       = 20;
const RATE_WINDOW_MS   = 60_000;
const MAX_INPUT_CHARS  = 8_000;

// In-memory rate-limit store: userId → { count, windowStart }
const rateLimitMap = new Map();

exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  };
  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers, body: '' };

  try {
    // ── Auth gate ──
    const token = (event.headers['authorization'] || event.headers['Authorization'] || '').replace(/^Bearer\s+/i, '');
    if (!token) return { statusCode: 401, headers, body: JSON.stringify({ error: 'unauthorized' }) };
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON, { auth: { persistSession: false } });
    const { data: { user }, error: authErr } = await supabase.auth.getUser(token);
    if (authErr || !user) return { statusCode: 401, headers, body: JSON.stringify({ error: 'unauthorized' }) };
    const userId = user.id;

    // ── Per-user rate limit (20 req / 60 s, in-memory) ──
    const now = Date.now();
    const windowStart = Math.floor(now / RATE_WINDOW_MS) * RATE_WINDOW_MS;
    const rl = rateLimitMap.get(userId);
    if (rl && rl.windowStart === windowStart) {
      if (rl.count >= RATE_LIMIT) {
        return { statusCode: 429, headers: { ...headers, 'Retry-After': '60' }, body: JSON.stringify({ error: 'Rate limit exceeded. Try again in a minute.' }) };
      }
      rl.count += 1;
    } else {
      rateLimitMap.set(userId, { count: 1, windowStart });
    }

    const { query, mode = 'chat', currency = 'USD', language = 'en' } = JSON.parse(event.body);

    // ── Input cap ──
    if (typeof query === 'string' && query.length > MAX_INPUT_CHARS) {
      return { statusCode: 413, headers, body: JSON.stringify({ error: 'Query too long. Maximum 8000 characters.' }) };
    }
    const apiKey = process.env.GROQ_API_KEY;
    if (!apiKey) return { statusCode: 500, headers, body: JSON.stringify({ error: 'GROQ_API_KEY not configured' }) };

    const isCanvas = mode === 'canvas';
    const langNames = { ru: 'Russian', de: 'German', es: 'Spanish', fr: 'French', ka: 'Georgian' };
    const langLine = language !== 'en' ? `\nRespond entirely in ${langNames[language] || 'English'}.` : '';

    const systemPrompt = isCanvas
      ? `You are SetAll Analyst — a ruthlessly precise financial data scientist.
CRITICAL: Your response MUST be valid JSON only. No markdown fences, no explanation, no extra text outside the JSON.
Required schema:
{
  "summary": "2-4 sentences of sharp, direct financial insight — use the actual numbers",
  "insights": ["3-5 specific actionable items referencing real values from the data"],
  "charts": [
    {
      "type": "bar|line|doughnut",
      "title": "descriptive chart title",
      "labels": ["label1", "label2"],
      "data": [12.5, 34.0],
      "backgroundColor": ["#14B8A6","#8B5CF6","#F59E0B","#EF4444","#3B82F6"]
    }
  ],
  "actions": []
}
Rules:
- Always include at least one chart when data supports it.
- Use doughnut for category breakdowns, bar for comparisons, line for time trends.
- backgroundColor must be an array of hex colours, one per data point.
- Be brutally specific with numbers. Call out waste. Flag anomalies.
- actions can contain "ADD_TREND" or "ADD_DONUT" to push extra widgets to the canvas.
- IMPORTANT: Always express monetary amounts in the user's currency: ${currency}. Do not use USD unless ${currency} is USD.${langLine}`
      : `You are SetAll AI — a direct, sharp financial strategist. Talk like a brilliant CFO to a peer. You have access to the user's real spending data in the message.
Rules:
- Be human. Be specific. Use the actual numbers from their data.
- 2-3 sentences max for simple questions. Go longer only if asked for detail.
- Zero filler: never say "Certainly!", "Great question!", "Based on the data provided", "I'd be happy to", "Of course!".
- For casual chat (hi, jokes, who are you): 1-2 natural sentences.
- Give real actionable advice, not generic financial tips.
- You may ask one follow-up question if genuinely useful.
- Respond in plain conversational text. No bullet points unless explicitly asked.
- IMPORTANT: Always express monetary amounts in the user's currency: ${currency}. Do not use USD unless ${currency} is USD.${langLine}`;

    const maxTokens   = isCanvas ? 2048 : 1024;
    const temperature = isCanvas ? 0.2 : 0.9;
    const model       = isCanvas ? 'llama-3.3-70b-versatile' : 'llama-3.1-8b-instant';

    const callGroq = async () => fetch(GROQ_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user',   content: query },
        ],
        max_tokens:  maxTokens,
        temperature,
      }),
    });

    let response = await callGroq();

    if (response.status === 429) {
      const retryAfter = response.headers.get('retry-after') || '3';
      await new Promise(r => setTimeout(r, parseInt(retryAfter) * 1000));
      response = await callGroq();
    }

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`Groq API ${response.status}: ${errText.slice(0, 400)}`);
    }

    const result  = await response.json();
    const rawText = result.choices?.[0]?.message?.content?.trim() || '';

    if (!rawText) {
      return { statusCode: 200, headers, body: JSON.stringify({ report: JSON.stringify({ summary: 'No response — try rephrasing.' }), mode }) };
    }

    if (isCanvas) {
      const cleaned   = rawText.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/```\s*$/g, '').trim();
      const jsonStart = cleaned.indexOf('{');
      let parsed = {};
      try {
        parsed = JSON.parse(jsonStart >= 0 ? cleaned.slice(jsonStart) : cleaned);
      } catch (_) {
        parsed = { summary: rawText.slice(0, 500) };
      }
      if (!parsed.summary) parsed.summary = rawText.slice(0, 300);
      return { statusCode: 200, headers, body: JSON.stringify({ report: JSON.stringify(parsed), mode: 'canvas' }) };
    } else {
      return { statusCode: 200, headers, body: JSON.stringify({ report: JSON.stringify({ summary: rawText }), mode: 'chat' }) };
    }

  } catch (error) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: error.message }) };
  }
};
