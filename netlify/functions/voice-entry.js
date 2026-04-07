// FEAT-VOICE: Voice entry parser — receives a transcript and returns a
// multi-action array. Uses Groq llama-3.3-70b-versatile.
// API key: process.env.GROQ_API_KEY (same env var as ai-analyst.js)
//
// Response shape:
//   { "actions": [ {type, ...}, ... ] }
//   Supported types: add_expense | add_income | create_group | add_member
//   Top-level needsClarification preserved for early-exit (empty/amount missing).

const GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions';

exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers, body: '' };

  try {
    const { transcript, groups = [], defaultCurrency = 'USD', knownCategories = [], language = 'en' } =
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
Parse the user's voice input into a JSON object with an "actions" array.

Each element in "actions" must have a "type" field. Supported types:

1. add_expense / add_income (use add_income when user means they received money):
   { "type": "add_expense", "amount": <number>, "currency": "<ISO>",
     "description": "<short label in user's language>", "category": "<from list>",
     "isIncome": false, "groupNameHint": "<group name or null>",
     "splitMode": "even", "needsClarification": null }

2. create_group:
   { "type": "create_group", "name": "<group name as user said it>" }

3. add_member:
   { "type": "add_member", "memberNameHint": "<person name as user said it>",
     "groupNameHint": "<group name or null>" }

Rules:
- Return ONLY the actions the user actually requested. Most transcripts = 1 action.
- Ordering: create_group first, then add_member, then add_expense/add_income.
- currency: 3-letter ISO. Infer from context:
  "lari"/"gel" → GEL, "dollar"/"usd" → USD, "euro" → EUR,
  "ruble"/"rub" → RUB, "yuan"/"rmb" → CNY, "dong" → VND, "dirham" → AED.
  If not mentioned, use defaultCurrency.
- isIncome: true ONLY if user says "received", "got paid", "salary",
  "income", "earned", "credited", "deposited". Default false.
- description: short label IN THE USER'S INPUT LANGUAGE. Do NOT translate.
  Keep it 3-6 words. Never include currency or amounts.
- category: pick exactly one from the knownCategories list.
- groupNameHint: group name as user said it (fuzzy). null if wallet/personal.
- splitMode: "even" by default. "none" only if user says "I paid for everyone"
  or "my share only" or "no split".
- needsClarification on an add_expense action: null if clear. Otherwise ONE of:
  "currency" | "group_not_found" | "amount" | "income_or_expense" | "group_name"

The voice input may be in any language. Parse correctly regardless of input language.
Always return JSON with English field names.

Respond ONLY with valid JSON. No explanation, no markdown, no preamble.

Example — single expense:
{"actions":[{"type":"add_expense","amount":50,"currency":"GEL","isIncome":false,"description":"Coffee Shop","category":"Food & drink","groupNameHint":null,"splitMode":"even","needsClarification":null}]}

Example — create group + add member + add expense:
{"actions":[{"type":"create_group","name":"Barcelona"},{"type":"add_member","memberNameHint":"Alex","groupNameHint":"Barcelona"},{"type":"add_expense","amount":120,"currency":"EUR","isIncome":false,"description":"Hotel","category":"Travel","groupNameHint":"Barcelona","splitMode":"even","needsClarification":null}]}`;

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
        max_tokens: 512,
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

    // Normalise: if LLM returned old flat shape (no actions key), wrap it
    if (!parsed.actions && !parsed.needsClarification) {
      parsed = { actions: [parsed] };
    }

    return { statusCode: 200, headers, body: JSON.stringify(parsed) };

  } catch (error) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: 'Parse failed' }) };
  }
};
