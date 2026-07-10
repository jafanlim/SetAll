// FEAT-RECEIPT: Receipt image ingest — receives the receipt image inline as base64,
// sends it to the OpenAI vision model, and returns a validated expense draft.
// Uses gpt-4.1 (single vision call; the app's 30s timeout + Netlify's ~26s sync cap rule out a 2-call escalation).
// PREMIUM OCR: if GOOGLE_VISION_API_KEY is set, the image is first transcribed by
//   Google Cloud Vision (DOCUMENT_TEXT_DETECTION) and the TEXT is structured by the
//   model — faithful non-Latin (Georgian) names instead of vision-LLM hallucination.
//   Absent the key, it falls back to the gpt-4.1 vision path. (Pay-to-use gate hook.)
// API keys: process.env.OPENAI_API_KEY (required), process.env.GOOGLE_VISION_API_KEY (optional).
// PRIVACY: the image is NEVER persisted — no Storage, no signed URL, no attachment.
//   It exists only in-memory for the duration of this request ("get context, don't store").
// SECURITY: Bearer token verified via supabase.auth.getUser; per-user rate limit 10/60s.
//
// Request:  { imageBase64, contentType, groupId?, defaultCurrency?, knownCategories?, timezone?, locale? }
// Response: { draft: { amount, currency, description, originalDescription, ... }, escalated: bool }
//           { needsClarification: "amount"|"currency"|"date", partial: { ... } }

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

// ── Structured-output schema (shared by the vision + OCR-text paths) ──
const RECEIPT_RESPONSE_FORMAT = {
  type: 'json_schema',
  json_schema: {
    name: 'receipt_draft',
    strict: true,
    schema: {
      type: 'object',
      properties: {
        amount:        { type: 'string', description: "Total amount as decimal string, e.g. '45.50'" },
        currency:      { type: 'string', description: 'ISO 4217 3-letter code' },
        description:            { type: 'string', description: 'Short label 3-6 words translated to locale' },
        original_description:  { type: 'string', description: 'Description in original language/script verbatim' },
        category:               { type: 'string' },
        merchant_name:          { type: 'string' },
        last4:         { type: ['string', 'null'], description: 'Card last 4 digits if visible, else null' },
        entry_date:    { type: 'string', description: 'ISO date YYYY-MM-DD from receipt, or today' },
        line_items:    {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              name:          { type: 'string' },
              original_name: { type: 'string', description: 'Item name exactly as printed, original script' },
              amount:        { type: 'string' },
              quantity:      { type: 'integer' },
            },
            required: ['name', 'original_name', 'amount', 'quantity'],
            additionalProperties: false,
          },
        },
        confidence:    { type: 'number', description: '0.0–1.0' },
        needs_clarification: { type: ['string', 'null'], enum: ['amount', 'currency', 'date', null] },
      },
      required: ['amount', 'currency', 'description', 'original_description', 'category', 'merchant_name',
                 'last4', 'entry_date', 'line_items', 'confidence', 'needs_clarification'],
      additionalProperties: false,
    },
  },
};

// ── Google Cloud Vision OCR (premium pre-pass) ──
// Dedicated OCR transcribes non-Latin scripts (Georgian, etc.) far better than a
// general vision LLM, which hallucinates item names. Returns {text, failReason}.
// The image is sent to Google for text extraction only; it is not persisted.
async function googleVisionOcr(apiKey, imageBase64, languageHints) {
  try {
    const resp = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requests: [{
          image: { content: imageBase64 },
          features: [{ type: 'DOCUMENT_TEXT_DETECTION' }],
          imageContext: languageHints ? { languageHints } : undefined,
        }],
      }),
    });
    if (!resp || !resp.ok) {
      const status = resp ? resp.status : 0;
      const reason = status === 429 ? 'quota' : `http_${status}`;
      console.warn('[receipt] Google Vision HTTP', status);
      return { text: null, failReason: reason };
    }
    const json = await resp.json();
    const r0 = json && json.responses && json.responses[0];
    if (r0 && r0.error) {
      console.warn('[receipt] Google Vision error', r0.error.code, r0.error.message);
      return { text: null, failReason: 'exception' };
    }
    const text = r0 && r0.fullTextAnnotation && r0.fullTextAnnotation.text;
    if (typeof text === 'string' && text.trim().length > 0) {
      return { text, failReason: null };
    }
    return { text: null, failReason: 'exception' };
  } catch (e) {
    console.warn('[receipt] Google Vision exception', e && e.message);
    return { text: null, failReason: 'exception' };
  }
}

// ── Vision OCR retry wrapper ──
// Retries EXACTLY ONCE on transient failure (429/5xx/network error) with ~1.5s
// backoff. Does NOT retry 400/403. Takes an injectable single-attempt callable
// (defaults to googleVisionOcr) so the retry logic is testable without network.
// Returns {text, failReason} where failReason ∈ 'quota'|'http_<status>'|'exception'|null.
async function visionOcrWithRetry(singleAttempt, apiKey, imageBase64, languageHints) {
  let result;
  try {
    result = await singleAttempt(apiKey, imageBase64, languageHints);
  } catch (e) {
    result = { text: null, failReason: 'exception' };
  }

  if (result.text !== null && result.text !== undefined && result.text.length > 0) {
    return { text: result.text, failReason: null };
  }

  // Only retry on transient failures: 429 (quota), 5xx, network/exception.
  const transient = result.failReason === 'quota' ||
                    (typeof result.failReason === 'string' && result.failReason.startsWith('http_5')) ||
                    result.failReason === 'exception';
  if (!transient) {
    return { text: null, failReason: result.failReason };
  }

  await new Promise(r => setTimeout(r, 1500));
  try {
    result = await singleAttempt(apiKey, imageBase64, languageHints);
  } catch (e) {
    result = { text: null, failReason: 'exception' };
  }

  if (result.text !== null && result.text !== undefined && result.text.length > 0) {
    return { text: result.text, failReason: null };
  }
  return { text: null, failReason: result.failReason };
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
    response_format: RECEIPT_RESPONSE_FORMAT,
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

// OCR-text path (premium): structure the dedicated-OCR transcript instead of an image.
function openaiChatCompletionFromText(apiKey, model, systemPrompt, ocrText, knownCategories) {
  const body = {
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      {
        role: 'user',
        content: [
          { type: 'text', text: `Receipt OCR transcript (verbatim from a dedicated OCR engine — use these exact names and numbers; do not invent or substitute):\n\n${ocrText}` },
          { type: 'text', text: `knownCategories: ${JSON.stringify(knownCategories)}` },
        ],
      },
    ],
    temperature: 0,
    response_format: RECEIPT_RESPONSE_FORMAT,
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

  // 7. lineItems: normalise (passthrough originalName for UI)
  const lineItems = (draft.line_items || []).map(li => ({
    name:         li.name || '',
    originalName: li.original_name || '',
    amount:       li.amount || '0',
    quantity:     li.quantity || 1,
  }));

  const responseDraft = {
    amount,
    currency,
    description,
    originalDescription: (draft.original_description || '').substring(0, MAX_DESCRIPTION),
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
    originalDescription: (draft.original_description || '').substring(0, MAX_DESCRIPTION),
    category,
    isIncome: false,
    merchantName: draft.merchant_name || '',
    last4,
    payerLabel,
    payerProfileId,
    lineItems: (draft.line_items || []).map(li => ({
      name:         li.name || '',
      originalName: li.original_name || '',
      amount:       li.amount || '0',
      quantity:     li.quantity || 1,
    })),
    entryDate: draft.entry_date || today,
    confidence: typeof draft.confidence === 'number' ? draft.confidence : 0,
  };
}

// ═══════════════════════════════════════════════════════════════
// Handler
// ═══════════════════════════════════════════════════════════════

exports.visionOcrWithRetry = visionOcrWithRetry;

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
    // Privacy: the receipt image is sent inline as base64 and used only to extract
    // a draft. It is NEVER persisted — no Supabase Storage, no signed URL, no
    // attachment on the saved expense. The image exists only in-memory for this call.
    const body = JSON.parse(event.body || '{}');
    const {
      imageBase64,
      contentType      = 'image/webp',
      groupId          = null,
      defaultCurrency  = 'USD',
      knownCategories  = STANDARD_CATEGORIES,
      timezone         = 'UTC',
    } = body;

    if (!imageBase64 || typeof imageBase64 !== 'string') {
      return { statusCode: 400, headers, body: JSON.stringify({ error: 'bad_request' }) };
    }

    // Size check on the decoded image (defense in depth; Netlify also caps the payload).
    const decodedBytes = Buffer.from(imageBase64, 'base64').length;
    if (decodedBytes === 0) {
      return { statusCode: 400, headers, body: JSON.stringify({ error: 'bad_request' }) };
    }
    if (decodedBytes > MAX_IMAGE_BYTES) {
      return { statusCode: 413, headers, body: JSON.stringify({ error: 'image_too_large' }) };
    }

    // Build data: URL straight from the provided base64 (sent to OpenAI).
    const imageContentType = /^image\/(webp|jpeg|jpg|png|heic)$/i.test(contentType) ? contentType : 'image/webp';
    const dataUrl = `data:${imageContentType};base64,${imageBase64}`;

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

    // ── System prompt (canonical from spec §2.1 — translate + keep original) ──
    const locale = (body.locale || 'en').substring(0, 2);
    const localeName = { en:'English', es:'Spanish', ru:'Russian', ar:'Arabic',
      ka:'Georgian', zh:'Chinese', ja:'Japanese', ko:'Korean', vi:'Vietnamese',
      fr:'French', de:'German', pt:'Portuguese', it:'Italian', nl:'Dutch',
      tr:'Turkish', th:'Thai', hi:'Hindi', id:'Indonesian', ms:'Malay',
      he:'Hebrew', pl:'Polish', uk:'Ukrainian', ro:'Romanian', hu:'Hungarian',
      cs:'Czech', sk:'Slovak', bg:'Bulgarian', sr:'Serbian', hr:'Croatian',
      fi:'Finnish', sv:'Swedish', da:'Danish', no:'Norwegian', el:'Greek',
    }[locale] || 'English';

    const systemPrompt = `You are a receipt parser for the SetAll expense-tracking app.
Extract structured data from the receipt image.

Rules:
- amount: the TOTAL amount paid (after tax, tips, discounts). Decimal string, e.g. "45.50".
- currency: 3-letter ISO code. Unambiguous symbols: €→EUR, £→GBP, ₾→GEL, ₽→RUB.
  '$' (USD/MXN/ARS/CLP/…) and '¥' (CNY/JPY) are REGION-AMBIGUOUS — for these use defaultCurrency
  from context unless the receipt explicitly names the code (e.g. "MXN", "US$", "MX$").
- description: merchant name or top item, 3-6 words, translated into ${localeName}.
- original_description: the receipt description in its ORIGINAL language and script, EXACTLY as
  printed. Do NOT translate or transliterate — keep original characters (Georgian, Cyrillic,
  Arabic, CJK, etc.) verbatim.
- category: pick exactly one from knownCategories.
- merchant_name: normalized merchant/store name. Do NOT translate merchant_name — it is a
  proper noun; keep it as printed.
- last4: last 4 digits of the card used, if visible on receipt. null if not visible.
  NEVER guess or invent a last4. Extract only if clearly printed.
- entry_date: date from receipt in YYYY-MM-DD. If not readable use today's date from context.
- line_items: array of individual line items. Empty array if not parseable.
  For each item:
  - name: the item name translated into ${localeName}.
  - original_name: the item name EXACTLY as printed on the receipt, in its original language
    and script (Georgian, Cyrillic, Arabic, CJK, etc.). Do NOT translate, transliterate, or
    reduce — keep the full descriptive text as shown, including non-Latin characters.
  - amount: the LINE TOTAL for this item — the price for the FULL quantity, exactly as
            printed on the receipt. Do NOT divide by quantity; do NOT return a per-unit price.
  - quantity: how many units (integer, default 1). Informational only — amount already
            covers the full quantity.
- confidence: your confidence 0.0–1.0 that the amount and currency are correct.
- needs_clarification: "amount" if total is unreadable, "currency" if indeterminate, "date" if
  date is critical and missing, null otherwise.

Merchant memory hints (learned from user's history):
${merchantHints || '(none yet)'}

Group item hints (for group_id ${groupId || 'none'}):
${itemHints || '(none yet)'}

Today's date: ${today}  Timezone: ${timezone}  Default currency: ${defaultCurrency}  Locale: ${localeName}`;

    // OCR-text variant of the prompt: same rules, but the text is already accurately
    // transcribed, so the model must NOT invent item names.
    const textSystemPrompt = systemPrompt.replace(
      'Extract structured data from the receipt image.',
      'You are given the OCR transcript of a receipt below (already extracted by a dedicated OCR engine — it is accurate). Use ONLY the item names and numbers that appear in it. NEVER invent, guess, or substitute item names; copy original_name VERBATIM from the transcript.',
    );

    // ── API key check ──
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      return { statusCode: 500, headers, body: JSON.stringify({ error: 'parse_failed' }) };
    }

    // ── OCR path selection ──
    // Premium: if Google Vision is configured, transcribe with dedicated OCR and
    // structure the TEXT (faithful non-Latin names). Otherwise fall back to the
    // gpt-4.1 vision call (which hallucinates non-Latin item names).
    const googleKey = process.env.GOOGLE_VISION_API_KEY;
    let ocrText = null;
    let ocrFailReason = googleKey ? null : 'no_key';
    if (googleKey) {
      // No languageHints — let Vision AUTO-DETECT the script. Hinting the user's UI
      // locale (e.g. 'ru') on a Georgian receipt produced mojibake / gibberish.
      const vr = await visionOcrWithRetry(googleVisionOcr, googleKey, imageBase64);
      ocrText = vr.text;
      ocrFailReason = vr.failReason;
    }
    const ocrUsed = !!(ocrText && ocrText.trim().length > 0);
    console.log('[receipt] OCR path', { keyPresent: !!googleKey, ocrUsed, ocrFailReason });

    const call = ocrUsed
      ? (model) => openaiChatCompletionFromText(apiKey, model, textSystemPrompt, ocrText, knownCategories)
      : (model) => openaiChatCompletion(apiKey, model, systemPrompt, dataUrl, knownCategories);

    // ── Single LLM call: gpt-4.1 (OCR-text structuring, or vision fallback) ──
    let openaiResponse = await call('gpt-4.1');

    // 429 retry (once)
    if (openaiResponse && openaiResponse.status === 429) {
      const retryAfter = openaiResponse.headers.get('retry-after') || '3';
      await new Promise(r => setTimeout(r, parseInt(retryAfter, 10) * 1000));
      openaiResponse = await call('gpt-4.1');
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

    // ── No escalation: gpt-4.1 is already the primary model (see above). A second vision
    //    call would push the request past the app's 30s timeout (Netlify caps sync fns at
    //    ~26s) — exactly what broke non-Latin receipts ("could not read it"). One call only.
    const escalated = false;

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
        ocr: ocrUsed,
        ocrFailReason: ocrFailReason || null,
      }),
    };

  } catch (_) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: 'parse_failed' }) };
  }
};
