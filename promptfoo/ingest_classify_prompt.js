/**
 * promptfoo dynamic prompt — SetAll bank-statement classifier eval.
 * Mirrors the classify system prompt in netlify/functions/ingest.js (classifyRows).
 * The user message is a single transaction row in the exact prod format
 * (`${i}: date=... amount=... CUR raw="..." income=...`), supplied via the `row` var.
 *
 * NOTE: this is the ACTUAL classifier path (Groq llama-3.3-70b-versatile). The old
 * "classify" cases lived in promptfooconfig.yaml (the ai-analyst CHAT eval), where the
 * fixture-grounded chat prompt refused out-of-fixture rows ("I don't have it") and the
 * assertions flaked. Classification is a separate prod feature with its own prompt.
 */
const FIXED_CATEGORIES = [
  'General', 'Food & drink', 'Transport', 'Entertainment',
  'Bills & utilities', 'Shopping', 'Travel', 'Other',
];

module.exports = function (context) {
  const { row = '' } = context.vars;

  const systemContent =
    `You are a bank statement classifier. Given transaction rows, classify each into exactly one category and generate a short description (3-5 words max).\n\n` +
    `Available categories: ${FIXED_CATEGORIES.map(c => `"${c}"`).join(', ')}\n\n` +
    `Rules:\n` +
    `- Pick the single best matching category from the list. Never invent a new one.\n` +
    `- Description: concise merchant/purpose label (e.g. "Coffee at Starbucks", "Monthly rent", "Spotify subscription").\n` +
    `- If a transaction looks like income (salary, refund, transfer in), prefer keeping the raw description.\n` +
    `- Return ONLY valid JSON — a JSON array, one object per row, in the same order as input.\n` +
    `- Each object: {"category": "...", "description": "..."}\n` +
    `- No markdown fences, no extra text.`;

  return [
    { role: 'system', content: systemContent },
    { role: 'user', content: row },
  ];
};
