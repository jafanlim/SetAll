// ingest.js — bank statement ingestion (CSV + text-PDF → classify → normalized rows)
// Auth + rate-limit: identical wrapper to ai-analyst.js (PROMPT-64).
// Extraction: pdf-parse for text PDFs; CSV is pre-parsed client-side via CsvAdapter.
// Classification: Groq llama-3.3-70b-versatile (server-side only).
// GROQ_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY must be set in Netlify env.

const { createClient } = require('@supabase/supabase-js');

const GROQ_API_URL    = 'https://api.groq.com/openai/v1/chat/completions';
const SUPABASE_URL    = process.env.SUPABASE_URL    || 'https://vrsmsgyxeyzyrdonsnrk.supabase.co';
const SUPABASE_ANON   = process.env.SUPABASE_ANON_KEY || '';
const RATE_LIMIT      = 10;
const RATE_WINDOW_MS  = 60_000;
const MAX_PDF_BYTES   = 5_000_000; // 5 MB

const FIXED_CATEGORIES = [
  'General', 'Food & drink', 'Transport', 'Entertainment',
  'Bills & utilities', 'Shopping', 'Travel', 'Other',
];

const rateLimitMap = new Map();

// ── Auth + rate-limit shared block (mirrors ai-analyst.js) ─────────────────
async function authenticate(event) {
  const token = (event.headers['authorization'] || event.headers['Authorization'] || '')
    .replace(/^Bearer\s+/i, '');
  if (!token) return { userId: null, error: 'unauthorized' };
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON, { auth: { persistSession: false } });
  const { data: { user }, error: authErr } = await supabase.auth.getUser(token);
  if (authErr || !user) return { userId: null, error: 'unauthorized' };
  return { userId: user.id, error: null, supabase };
}

function checkRateLimit(userId) {
  const now = Date.now();
  const windowStart = Math.floor(now / RATE_WINDOW_MS) * RATE_WINDOW_MS;
  const rl = rateLimitMap.get(userId);
  if (rl && rl.windowStart === windowStart) {
    if (rl.count >= RATE_LIMIT) return false;
    rl.count += 1;
  } else {
    rateLimitMap.set(userId, { count: 1, windowStart });
  }
  return true;
}

// ── PDF text extraction ─────────────────────────────────────────────────────
// pdf-parse is lazy-required so cold starts don't fail if the dep is absent.
async function extractPdfText(base64Data) {
  let pdfParse;
  try {
    pdfParse = require('pdf-parse');
  } catch (_) {
    throw new Error('pdf-parse not installed. Run npm install pdf-parse.');
  }
  const buffer = Buffer.from(base64Data, 'base64');
  if (buffer.byteLength > MAX_PDF_BYTES) throw new Error('PDF too large (max 5 MB)');
  const data = await pdfParse(buffer);
  return data.text || '';
}

// ── Groq classify call ──────────────────────────────────────────────────────
const callGroq = (apiKey, messages) =>
  fetch(GROQ_API_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${apiKey}` },
    body: JSON.stringify({
      model: 'llama-3.3-70b-versatile',
      messages,
      max_tokens: 4096,
      temperature: 0.1,
    }),
  });

// ── Transaction row parser (raw text → candidate rows) ─────────────────────
// Handles common bank statement line formats.
// Returns [{date, amount, currency, raw_description}]
function parseTransactionLines(text) {
  const rows = [];
  const lines = text.split(/\r?\n/);

  // Patterns: date + amount (with optional currency symbol) + description
  // Covers: "2024-01-15  -45.00  Coffee Shop"
  //         "15/01/2024  GBP 45.00  Tesco"
  //         "Jan 15, 2024  $45.00  Amazon"
  const dateRe = /(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4}|\d{4}[\/\-]\d{2}[\/\-]\d{2}|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4})/i;
  const amtRe  = /([A-Z]{3})?\s*([+\-]?\s*[\d,]+\.?\d*)/;

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.length < 5) continue;

    const dateMatch = trimmed.match(dateRe);
    if (!dateMatch) continue;

    // Find amount: look for number with optional currency prefix after the date
    const afterDate = trimmed.slice(dateMatch.index + dateMatch[0].length).trim();
    const amtMatch  = afterDate.match(amtRe);
    if (!amtMatch) continue;

    const rawAmt = amtMatch[0].replace(/,/g, '').trim();
    const numStr = rawAmt.replace(/[A-Z\s]/g, '');
    const num    = parseFloat(numStr);
    if (!isFinite(num) || num === 0) continue;

    const currency = amtMatch[1] || 'USD';
    // Description = everything after the amount match
    const descStart = afterDate.indexOf(amtMatch[0]) + amtMatch[0].length;
    const raw_description = afterDate.slice(descStart).trim() || trimmed;

    // Normalise date
    let parsedDate = null;
    try {
      parsedDate = new Date(dateMatch[0]).toISOString().slice(0, 10);
      if (parsedDate === 'Invalid Date') parsedDate = null;
    } catch (_) {}
    if (!parsedDate) continue;

    rows.push({
      date: parsedDate,
      amount: Math.abs(num).toFixed(2),
      currency: currency.toUpperCase(),
      raw_description,
      is_income: num > 0,
    });
  }
  return rows;
}

// ── Groq: classify + describe a batch of rows ───────────────────────────────
async function classifyRows(apiKey, rows, userCategories) {
  const allCats = [...FIXED_CATEGORIES, ...userCategories.map(c => c.name)];

  const systemPrompt = `You are a bank statement classifier. Given transaction rows, classify each into exactly one category and generate a short description (3-5 words max).

Available categories: ${allCats.map(c => `"${c}"`).join(', ')}

Rules:
- Pick the single best matching category from the list. Never invent a new one.
- Description: concise merchant/purpose label (e.g. "Coffee at Starbucks", "Monthly rent", "Spotify subscription").
- If a transaction looks like income (salary, refund, transfer in), prefer keeping the raw description.
- Return ONLY valid JSON — a JSON array, one object per row, in the same order as input.
- Each object: {"category": "...", "description": "..."}
- No markdown fences, no extra text.`;

  const userMsg = rows.map((r, i) =>
    `${i}: date=${r.date} amount=${r.amount} ${r.currency} raw="${r.raw_description}" income=${r.is_income}`
  ).join('\n');

  let resp = await callGroq(apiKey, [
    { role: 'system', content: systemPrompt },
    { role: 'user',   content: userMsg },
  ]);

  if (resp.status === 429) {
    const ra = resp.headers.get('retry-after') || '5';
    await new Promise(r => setTimeout(r, parseInt(ra) * 1000));
    resp = await callGroq(apiKey, [
      { role: 'system', content: systemPrompt },
      { role: 'user',   content: userMsg },
    ]);
  }

  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`Groq classify ${resp.status}: ${txt.slice(0, 300)}`);
  }

  const groqData = await resp.json();
  const raw = groqData.choices?.[0]?.message?.content?.trim() || '[]';
  const cleaned = raw.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/```\s*$/g, '').trim();
  const jsonStart = cleaned.indexOf('[');
  let parsed = [];
  try {
    parsed = JSON.parse(jsonStart >= 0 ? cleaned.slice(jsonStart) : cleaned);
  } catch (_) {
    parsed = [];
  }

  // Merge classification back into rows
  return rows.map((r, i) => {
    const cls = Array.isArray(parsed) && parsed[i] ? parsed[i] : {};
    const cat = allCats.includes(cls.category) ? cls.category : 'General';
    return {
      ...r,
      category:    cat,
      description: cls.description || r.raw_description,
    };
  });
}

// ── Handler ─────────────────────────────────────────────────────────────────
exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers, body: '' };

  const fail = (code, msg) => ({ statusCode: code, headers, body: JSON.stringify({ error: msg }) });

  try {
    // ── Auth ──
    const { userId, error: authErr } = await authenticate(event);
    if (authErr) return fail(401, authErr);

    // ── Rate limit ──
    if (!checkRateLimit(userId)) {
      return { statusCode: 429, headers: { ...headers, 'Retry-After': '60' },
        body: JSON.stringify({ error: 'Rate limit exceeded. Try again in a minute.' }) };
    }

    const apiKey = process.env.GROQ_API_KEY;
    if (!apiKey) return fail(500, 'GROQ_API_KEY not configured');

    const body = JSON.parse(event.body || '{}');
    const { format, csvRows, pdfBase64, userCategories = [] } = body;

    // ── Route by format ──
    let rawRows = [];

    if (format === 'csv') {
      // CSV rows are pre-parsed by CsvAdapter on the client and sent as normalized objects.
      // Expected: [{date, amount, currency, raw_description, is_income}]
      if (!Array.isArray(csvRows) || csvRows.length === 0) return fail(400, 'csvRows required for CSV format');
      if (csvRows.length > 500) return fail(413, 'Too many rows (max 500)');
      rawRows = csvRows.map(r => ({
        date:            r.date            || '',
        amount:          String(r.amount   || '0'),
        currency:        (r.currency       || 'USD').toUpperCase(),
        raw_description: r.raw_description || r.description || '',
        is_income:       Boolean(r.is_income),
      })).filter(r => r.date && parseFloat(r.amount) > 0);

    } else if (format === 'pdf') {
      if (!pdfBase64) return fail(400, 'pdfBase64 required for PDF format');
      const text = await extractPdfText(pdfBase64);
      if (!text.trim()) return fail(422, 'No extractable text found in PDF. Only text-based PDFs are supported.');
      rawRows = parseTransactionLines(text);
      if (rawRows.length === 0) return fail(422, 'No transaction rows could be parsed from this PDF.');

    } else {
      return fail(400, 'format must be "csv" or "pdf"');
    }

    // ── Classify in batches of 50 (Groq context safety) ──
    const BATCH = 50;
    const classified = [];
    for (let i = 0; i < rawRows.length; i += BATCH) {
      const batch = rawRows.slice(i, i + BATCH);
      const result = await classifyRows(apiKey, batch, userCategories);
      classified.push(...result);
    }

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({ rows: classified, count: classified.length }),
    };

  } catch (err) {
    return fail(500, err.message);
  }
};
