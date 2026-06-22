// FEAT-RECEIPT: Receipt image ingest — receives a Supabase signed URL for a
// receipt image, fetches it server-side, sends base64 to OpenAI vision model,
// and returns a validated expense draft. Uses gpt-4.1-mini (escalates to
// gpt-4.1 on confidence < 0.7). API key: process.env.OPENAI_API_KEY.
// SECURITY: Bearer token verified via supabase.auth.getUser; per-user rate limit 10/60s.
//
// Response shape:
//   { draft: { amount, currency, description, ... }, escalated: bool, imageStoragePath: "..." }
//   { needsClarification: "amount"|"currency"|"date", partial: { ... } }

const { createClient } = require('@supabase/supabase-js');

const OPENAI_API_URL    = 'https://api.openai.com/v1/chat/completions';
const SUPABASE_URL      = process.env.SUPABASE_URL     || 'https://vrsmsgyxeyzyrdonsnrk.supabase.co';
const SUPABASE_ANON     = process.env.SUPABASE_ANON_KEY || '';
const RATE_LIMIT        = 10;
const RATE_WINDOW_MS    = 60_000;
const MAX_IMAGE_BYTES   = 4 * 1024 * 1024;  // 4 MB
const MAX_AMOUNT_CENTS  = 100_000_000;       // 1_000_000.00 USD in cents
const MAX_DESCRIPTION   = 120;

const STANDARD_CATEGORIES = [
  'Food & drink', 'Transport', 'Shopping', 'Entertainment',
  'Bills', 'Health', 'Travel', 'General',
];

// In-memory rate-limit store: userId → { count, windowStart }
const rateLimitMap = new Map();

// ── Integer-cents helpers (no float math for money) ──

// Parse decimal string → integer cents. Returns NaN on invalid input.
function amountToCents(s) {
  s = (s || '').trim();
  const m = s.match(/^(-?\d+)(?:\.(\d{1,2}))?$/);
  if (!m) return NaN;
  const intPart  = parseInt(m[1], 10);
  const fracPart = parseInt((m[2] || '0').padEnd(2, '0'), 10);
  const sign = s.startsWith('-') ? -1 : 1;
  return sign * (intPart * 100 + fracPart);
}

// Convert integer cents back to a decimal string "123.45".
function centsToAmount(cents) {
  if (cents < 1) return '0.01';
  if (cents > MAX_AMOUNT_CENTS) cents = MAX_AMOUNT_CENTS;
  const intPart  = Math.floor(cents / 100);
  const fracPart = String(cents % 100).padStart(2, '0');
  return `${intPart}.${fracPart}`;
}

// ── Image path parser ──

// Parse object path from Supabase signed URL:
//   .../storage/v1/object/sign/<bucket>/<path>?token=...
// Returns the path without the bucket prefix (matching repo attachment paths).
function parseImageStoragePath(signedUrl) {
  try {
    const url = new URL(signedUrl);
    const marker = '/object/sign/';
    const idx = url.pathname.indexOf(marker);
    if (idx === -1) return null;
    const bucketAndPath = url.pathname.slice(idx + marker.length); // "<bucket>/<path>"
    const slash = bucketAndPath.indexOf('/');
    return slash === -1 ? null : decodeURIComponent(bucketAndPath.slice(slash + 1));
  } catch {
    return null;
  }
}

// ── OpenAI call helper (returns fetch Response or null on network error) ──

async function openaiChatCompletion(apiKey, model, systemPrompt, dataUrl, knownCategories) {
  const body = {
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      {
        role: 'user',
        content: [
          { type: 'image_url', image_url: { url: dataUrl, detail: 'high' } },
          { type: 'text', text: `knownCategories: ${JSON.stringify(knownCategories)}` },
        ],
      },
    ],
    temperature: 0,
    response_format: {
      type: 'json_schema',
      json_schema: {
        name: 'receipt_draft',
        strict: true,
        schema: {
          type: 'object',
          properties: {
            amount:        { type: 'string', description: "Total amount as decimal string, e.g. '45.50'" },
            currency:      { type: 'string', description: 'ISO 4217 3-letter code' },
            description:   { type: 'string', description: 'Short label 3-6 words' },
            category:      { type: 'string' },
            merchant_name: { type: 'string' },
            last4:         { type: ['string', 'null'], description: 'Card last 4 digits if visible, else null' },
            entry_date:    { type: 'string', description: 'ISO date YYYY-MM-DD from receipt, or today' },
            line_items:    {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  name:     { type: 'string' },
                  amount:   { type: 'string' },
                  quantity: { type: 'integer' },
                },
                required: ['name', 'amount', 'quantity'],
                additionalProperties: false,
              },
            },
            confidence:    { type: 'number', description: '0.0–1.0' },
            needs_clarification: { type: ['string', 'null'], enum: ['amount', 'currency', 'date', null] },
          },
          required: ['amount', 'currency', 'description', 'category', 'merchant_name',
                     'last4', 'entry_date', 'line_items', 'confidence', 'needs_clarification'],
          additionalProperties: false,
        },
      },
    },
  };

  return fetch(OPENAI_API_URL, {
    method: 'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });
}

// ── Server-side validation + draft assembly ──

function validateAndBuild(draft, defaultCurrency, knownCategories, paymentMethods, today) {
  // 1. Amount: parse as integer cents
  const amountCents = amountToCents(draft.amount);
  if (isNaN(amountCents) || amountCents <= 0) {
    return { needsClarification: 'amount', partial: buildPartial(draft, defaultCurrency, knownCategories, paymentMethods, today) };
  }

  // 2. Clamp amount to [0.01, 1_000_000]
  const clampedCents = Math.min(Math.max(amountCents, 1), MAX_AMOUNT_CENTS);
  const amount = centsToAmount(clampedCents);

  // 3. Currency: must be 3-letter uppercase, else fallback
  const currencyRaw = (draft.currency || '').toUpperCase();
  const currency = /^[A-Z]{3}$/.test(currencyRaw) ? currencyRaw : defaultCurrency;

  // 4. Description: truncate to 120 chars
  const description = (draft.description || '').substring(0, MAX_DESCRIPTION);

  // 5. Category: must be in knownCategories, else "General"
  let category = draft.category || 'General';
  if (!knownCategories.includes(category)) category = 'General';

  // 6. last4 → payer lookup (server-side, not model decision)
  let last4 = draft.last4 || null;
  let payerLabel = null;
  let payerProfileId = null;
  if (last4 && typeof last4 === 'string' && /^\d{4}$/.test(last4)) {
    const match = paymentMethods.find(pm => pm.last4 === last4);
    if (match) {
      payerLabel      = match.label;
      payerProfileId  = match.owner_profile_id || null;
    } else {
      // last4 found on receipt but unknown to server → null the label
      payerLabel = null;
    }
  } else {
    last4 = null;
  }

  // 7. lineItems: normalise
  const lineItems = (draft.line_items || []).map(li => ({
    name:     li.name || '',
    amount:   li.amount || '0',
    quantity: li.quantity || 1,
  }));

  const responseDraft = {
    amount,
    currency,
    description,
    category,
    isIncome: false,
    merchantName: draft.merchant_name || '',
    last4,
    payerLabel,
    payerProfileId,
    lineItems,
    entryDate: draft.entry_date || today,
    confidence: typeof draft.confidence === 'number' ? draft.confidence : 0,
  };

  // 8. Model-level needs_clarification
  if (draft.needs_clarification && ['amount', 'currency', 'date'].includes(draft.needs_clarification)) {
    return { needsClarification: draft.needs_clarification, partial: responseDraft };
  }

  return { draft: responseDraft };
}

function buildPartial(draft, defaultCurrency, knownCategories, paymentMethods, today) {
  const currencyRaw = (draft.currency || '').toUpperCase();
  const currency = /^[A-Z]{3}$/.test(currencyRaw) ? currencyRaw : defaultCurrency;

  let category = draft.category || 'General';
  if (!knownCategories.includes(category)) category = 'General';

  let last4 = draft.last4 || null;
  let payerLabel = null;
  let payerProfileId = null;
  if (last4 && typeof last4 === 'string' && /^\d{4}$/.test(last4)) {
    const match = paymentMethods.find(pm => pm.last4 === last4);
    if (match) {
      payerLabel      = match.label;
      payerProfileId  = match.owner_profile_id || null;
    } else {
      payerLabel = null;
    }
  } else {
    last4 = null;
  }

  return {
    amount: draft.amount || '0',
    currency,
    description: (draft.description || '').substring(0, MAX_DESCRIPTION),
    category,
    isIncome: false,
    merchantName: draft.merchant_name || '',
    last4,
    payerLabel,
    payerProfileId,
    lineItems: (draft.line_items || []).map(li => ({
      name:     li.name || '',
      amount:   li.amount || '0',
      quantity: li.quantity || 1,
    })),
    entryDate: draft.entry_date || today,
    confidence: typeof draft.confidence === 'number' ? draft.confidence : 0,
  };
}

// ═══════════════════════════════════════════════════════════════
// Handler
// ═══════════════════════════════════════════════════════════════

exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin':  '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers, body: '' };

  try {
    // ── Auth gate ──
    const token = (event.headers['authorization'] || event.headers['Authorization'] || '').replace(/^Bearer\s+/i, '');
    if (!token) return { statusCode: 401, headers, body: JSON.stringify({ error: 'unauthorized' }) };
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON, {
      auth: { persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: { user }, error: authErr } = await supabase.auth.getUser(token);
    if (authErr || !user) return { statusCode: 401, headers, body: JSON.stringify({ error: 'unauthorized' }) };
    const userId = user.id;

    // ── Per-user rate limit (10 req / 60 s, in-memory) ──
    const now = Date.now();
    const windowStart = Math.floor(now / RATE_WINDOW_MS) * RATE_WINDOW_MS;
    const rl = rateLimitMap.get(userId);
    if (rl && rl.windowStart === windowStart) {
      if (rl.count >= RATE_LIMIT) {
        return { statusCode: 429, headers: { ...headers, 'Retry-After': '60' }, body: JSON.stringify({ error: 'rate_limit_exceeded' }) };
      }
      rl.count += 1;
    } else {
      rateLimitMap.set(userId, { count: 1, windowStart });
    }

    // ── Parse + validate body ──
    const body = JSON.parse(event.body || '{}');
    const {
      signedUrl,
      groupId          = null,
      defaultCurrency  = 'USD',
      knownCategories  = STANDARD_CATEGORIES,
      timezone         = 'UTC',
    } = body;

    if (!signedUrl || !signedUrl.startsWith('https://')) {
      return { statusCode: 400, headers, body: JSON.stringify({ error: 'bad_request' }) };
    }

    // ── Derive image storage path from signed URL ──
    const imageStoragePath = parseImageStoragePath(signedUrl);

    // ── Fetch image server-side ──
    let imageResponse;
    try {
      imageResponse = await fetch(signedUrl);
    } catch (_) {
      return { statusCode: 400, headers, body: JSON.stringify({ error: 'bad_request' }) };
    }
    if (!imageResponse.ok) {
      return { statusCode: 400, headers, body: JSON.stringify({ error: 'bad_request' }) };
    }

    // Size check (try content-length header first, then actual buffer)
    const contentLength = imageResponse.headers.get('content-length');
    if (contentLength && parseInt(contentLength, 10) > MAX_IMAGE_BYTES) {
      return { statusCode: 413, headers, body: JSON.stringify({ error: 'image_too_large' }) };
    }

    const imageBuffer = await imageResponse.arrayBuffer();
    if (imageBuffer.byteLength > MAX_IMAGE_BYTES) {
      return { statusCode: 413, headers, body: JSON.stringify({ error: 'image_too_large' }) };
    }

    // Base64-encode → data: URL (send to OpenAI, NOT the raw signedUrl)
    const base64Image = Buffer.from(imageBuffer).toString('base64');
    const imageContentType = imageResponse.headers.get('content-type') || 'image/jpeg';
    const dataUrl = `data:${imageContentType};base64,${base64Image}`;

    // ── Memory retrieval (RLS-scoped via user JWT) ──
    const merchantPromise = supabase
      .from('merchant_memory')
      .select('merchant_name, category')
      .eq('user_id', userId)
      .order('hit_count', { ascending: false })
      .limit(5);

    const paymentPromise = supabase
      .from('payment_methods')
      .select('last4, label, owner_profile_id')
      .eq('user_id', userId);

    const itemPromise = groupId
      ? supabase
          .from('item_memory')
          .select('item_name, category')
          .eq('group_id', groupId)
          .order('hit_count', { ascending: false })
          .limit(10)
      : Promise.resolve({ data: [] });

    const [merchantResult, paymentResult, itemResult] =
      await Promise.all([merchantPromise, paymentPromise, itemPromise]);

    const merchantHints = (merchantResult.data || [])
      .map(m => `${m.merchant_name} → ${m.category}`)
      .join('\n');

    const itemHints = (itemResult.data || [])
      .map(i => `${i.item_name} → ${i.category}`)
      .join('\n');

    const paymentMethods = paymentResult.data || [];

    // ── Today's date ──
    const today = new Date().toISOString().split('T')[0];

    // ── System prompt (canonical from spec §1.1) ──
    const systemPrompt = `You are a receipt parser for the SetAll expense-tracking app.
Extract structured data from the receipt image.

Rules:
- amount: the TOTAL amount paid (after tax, tips, discounts). Decimal string, e.g. "45.50".
- currency: 3-letter ISO code. Infer from symbol ($→USD, €→EUR, £→GBP, ₾→GEL, ₽→RUB, ¥→CNY).
  If ambiguous use defaultCurrency from context.
- description: merchant name or top item, 3-6 words, in the receipt's language.
- category: pick exactly one from knownCategories.
- merchant_name: normalized merchant/store name.
- last4: last 4 digits of the card used, if visible on receipt. null if not visible.
  NEVER guess or invent a last4. Extract only if clearly printed.
- entry_date: date from receipt in YYYY-MM-DD. If not readable use today's date from context.
- line_items: array of individual line items (name, amount, quantity). Empty array if not parseable.
- confidence: your confidence 0.0–1.0 that the amount and currency are correct.
- needs_clarification: "amount" if total is unreadable, "currency" if indeterminate, "date" if
  date is critical and missing, null otherwise.

Merchant memory hints (learned from user's history):
${merchantHints || '(none yet)'}

Group item hints (for group_id ${groupId || 'none'}):
${itemHints || '(none yet)'}

Today's date: ${today}  Timezone: ${timezone}  Default currency: ${defaultCurrency}`;

    // ── API key check ──
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      return { statusCode: 500, headers, body: JSON.stringify({ error: 'parse_failed' }) };
    }

    // ── Call helper ──
    const call = (model) => openaiChatCompletion(apiKey, model, systemPrompt, dataUrl, knownCategories);

    // ── Primary call: gpt-4.1-mini ──
    let openaiResponse = await call('gpt-4.1-mini');

    // 429 retry (once)
    if (openaiResponse && openaiResponse.status === 429) {
      const retryAfter = openaiResponse.headers.get('retry-after') || '3';
      await new Promise(r => setTimeout(r, parseInt(retryAfter, 10) * 1000));
      openaiResponse = await call('gpt-4.1-mini');
    }

    // Still 429 after retry → 503
    if (openaiResponse && openaiResponse.status === 429) {
      return { statusCode: 503, headers, body: JSON.stringify({ error: 'upstream_unavailable' }) };
    }

    if (!openaiResponse || !openaiResponse.ok) {
      return { statusCode: 500, headers, body: JSON.stringify({ error: 'parse_failed' }) };
    }

    const result  = await openaiResponse.json();
    const rawText = result.choices?.[0]?.message?.content;

    if (!rawText) {
      return { statusCode: 500, headers, body: JSON.stringify({ error: 'parse_failed' }) };
    }

    // Parse structured output (strict: true → should always be valid JSON)
    let draft;
    try {
      draft = typeof rawText === 'string' ? JSON.parse(rawText) : rawText;
    } catch (_) {
      return { statusCode: 500, headers, body: JSON.stringify({ error: 'parse_failed' }) };
    }

    // ── Escalation: confidence < 0.7 → retry with gpt-4.1 (max 1 escalation) ──
    let escalated = false;
    if (typeof draft.confidence === 'number' && draft.confidence < 0.7) {
      let esResponse = await call('gpt-4.1');

      if (esResponse && esResponse.status === 429) {
        const retryAfter = esResponse.headers.get('retry-after') || '3';
        await new Promise(r => setTimeout(r, parseInt(retryAfter, 10) * 1000));
        esResponse = await call('gpt-4.1');
      }

      if (esResponse && esResponse.status === 429) {
        return { statusCode: 503, headers, body: JSON.stringify({ error: 'upstream_unavailable' }) };
      }

      if (esResponse && esResponse.ok) {
        const esResult  = await esResponse.json();
        const esRawText = esResult.choices?.[0]?.message?.content;
        if (esRawText) {
          try {
            draft     = typeof esRawText === 'string' ? JSON.parse(esRawText) : esRawText;
            escalated = true;
          } catch (_) { /* keep original low-confidence draft, escalated stays false */ }
        }
      }
      // If escalation call failed (non-429, non-ok), keep original draft
    }

    // ── Server-side validation + clamping ──
    const validated = validateAndBuild(draft, defaultCurrency, knownCategories, paymentMethods, today);

    if (validated.needsClarification) {
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          needsClarification: validated.needsClarification,
          partial: validated.partial,
        }),
      };
    }

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        draft: validated.draft,
        escalated,
        imageStoragePath,
      }),
    };

  } catch (_) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: 'parse_failed' }) };
  }
};
