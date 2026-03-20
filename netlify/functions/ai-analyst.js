// CHORE-01: Active path for setall.app web portal ONLY.
// Flutter client uses supabase/functions/ai-analyst/index.ts directly.
// Keep both in sync when changing model, prompt, or response shape.
exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  };
  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers, body: '' };

  try {
    const { query, mode = 'chat' } = JSON.parse(event.body);
    const apiKey = process.env.Gemini || process.env.GEMINI_API_KEY;
    if (!apiKey) return { statusCode: 500, headers, body: JSON.stringify({ error: 'GEMINI_API_KEY not configured' }) };

    const isCanvas = mode === 'canvas';

    // Two models: fast conversational for chat, reasoning model for deep analysis
    const model = isCanvas ? 'gemini-2.5-flash' : 'gemini-2.5-flash-lite';

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
- actions can contain "ADD_TREND" or "ADD_DONUT" to push extra widgets to the canvas.`
      : `You are SetAll AI — a direct, sharp financial strategist. Talk like a brilliant CFO to a peer. You have access to the user's real spending data in the message.
Rules:
- Be human. Be specific. Use the actual numbers from their data.
- 2-3 sentences max for simple questions. Go longer only if asked for detail.
- Zero filler: never say "Certainly!", "Great question!", "Based on the data provided", "I'd be happy to", "Of course!".
- For casual chat (hi, jokes, who are you): 1-2 natural sentences.
- Give real actionable advice, not generic financial tips.
- You may ask one follow-up question if genuinely useful.
- Respond in plain conversational text. No bullet points unless explicitly asked.`;

    const generationConfig = isCanvas
      ? { temperature: 0.2, maxOutputTokens: 8192 }
      : { temperature: 0.9, maxOutputTokens: 1024 };

    const safetySettings = [
      { category: 'HARM_CATEGORY_HARASSMENT',        threshold: 'BLOCK_NONE' },
      { category: 'HARM_CATEGORY_HATE_SPEECH',       threshold: 'BLOCK_NONE' },
      { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_NONE' },
      { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_NONE' },
    ];

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: systemPrompt }] },
          contents:           [{ parts: [{ text: query }] }],
          generationConfig,
          safetySettings,
        })
      }
    );

    if (!response.ok) {
      const errText = await response.text();
      if (response.status === 429) {
        const retryAfter = response.headers.get('retry-after') || response.headers.get('x-ratelimit-reset-requests');
        const waitMsg = retryAfter ? ` Retry after ${retryAfter}s.` : ' Try again in a moment.';
        let detail = '';
        try { detail = JSON.parse(errText)?.error?.message || ''; } catch (_) {}
        throw new Error(`Rate limited (429).${waitMsg}${detail ? ' ' + detail : ''}`);
      }
      throw new Error(`Gemini API ${response.status}: ${errText.slice(0, 400)}`);
    }

    const result  = await response.json();
    const parts   = result.candidates?.[0]?.content?.parts ?? [];
    const actual  = parts.find(p => p.text && !p.thought);
    const rawText = actual?.text?.trim() || '';

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
