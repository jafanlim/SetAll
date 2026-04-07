// FEAT-VOICE: Voice entry parser — receives a transcript and returns structured
// JSON for expense/income creation. Uses Groq llama-3.3-70b-versatile.
// API key: process.env.GROQ_API_KEY (same env var as ai-analyst.js)

const GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions';

exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers, body: '' };

  try {
    const { transcript, groups = [], defaultCurrency = 'USD', knownCategories = [] } =
      JSON.parse(event.body || '{}');

    if (!transcript || transcript.trim() === '') {
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({ needsClarification: 'amount' }),
      };
    }

    const apiKey = process.env.GROQ_API_KEY;
    if (!apiKey) {
      return {
        statusCode: 500,
        headers,
        body: JSON.stringify({ error: 'GROQ_API_KEY not configured' }),
      };
    }

    const systemPrompt = `You are a financial entry parser for the SetAll expense-tracking app.
Parse the user's voice input into a structured JSON object.

Rules:
- type: "wallet" if personal expense/income, "group" if user mentions a group name
- amount: numeric value only, no currency symbol
- currency: 3-letter ISO code. Infer from context:
  "lari" or "gel" → GEL, "dollar" or "usd" → USD, "euro" → EUR,
  "ruble" or "rub" → RUB, "yuan" or "rmb" → CNY, "dong" → VND,
  "dirham" → AED. If not mentioned, use defaultCurrency.
- isIncome: true ONLY if user says "received", "got paid", "salary",
  "income", "earned", "credited", "deposited". Default false.
- description: clean title-case phrase describing what was purchased or paid for.
  Keep it short (3-6 words). Never include currency or amounts.
- category: pick exactly one from knownCategories list provided.
- groupNameHint: the group name as the user said it (fuzzy). null if type=wallet.
- splitMode: "even" by default. "none" only if user says "I paid for everyone"
  or "my share only" or "no split".
- needsClarification: null if all required fields are clear. Otherwise ONE of:
  "currency" | "group_not_found" | "amount" | "income_or_expense" | "group_name"

Respond ONLY with valid JSON. No explanation, no markdown backticks, no preamble.

Example output:
{"type":"wallet","amount":50,"currency":"GEL","isIncome":false,
 "description":"Coffee Shop","category":"Food & drink",
 "groupNameHint":null,"splitMode":"even","needsClarification":null}`;

    const userMessage = `${transcript}\n\nContext: defaultCurrency=${defaultCurrency} (IMPORTANT: use ${defaultCurrency} if no currency mentioned), groups=${JSON.stringify(groups)}, categories=${knownCategories.join(',')}`;

    const callGroq = async () => fetch(GROQ_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: 'llama-3.3-70b-versatile',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user',   content: userMessage },
        ],
        max_tokens: 256,
        temperature: 0.1,
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
      return { statusCode: 500, headers, body: JSON.stringify({ error: 'Parse failed' }) };
    }

    // Strip any accidental markdown fences
    const cleaned   = rawText.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/```\s*$/g, '').trim();
    const jsonStart = cleaned.indexOf('{');
    let parsed;
    try {
      parsed = JSON.parse(jsonStart >= 0 ? cleaned.slice(jsonStart) : cleaned);
    } catch (_) {
      return { statusCode: 500, headers, body: JSON.stringify({ error: 'Parse failed' }) };
    }

    return { statusCode: 200, headers, body: JSON.stringify(parsed) };

  } catch (error) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: 'Parse failed' }) };
  }
};
