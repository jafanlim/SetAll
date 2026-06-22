/**
 * promptfoo dynamic prompt — SetAll receipt-ingest eval
 * Returns an OpenAI-compatible messages array with vars interpolated.
 * Mirrors the prod system prompt and message structure from
 * netlify/functions/receipt-ingest.js L340-364 (systemPrompt) and L56-68 (messages).
 *
 * Fixture images are loaded from disk, base64-encoded, and sent as data: URLs.
 * This eval hits the OpenAI API directly (not the deployed fn).
 */
const fs = require('fs');
const path = require('path');

module.exports = function (context) {
  const {
    fixtureImage   = '',
    knownCategories = ['Food & drink', 'Transport', 'Shopping', 'Entertainment', 'Bills', 'Health', 'Travel', 'General'],
    defaultCurrency = 'USD',
    timezone        = 'UTC',
    today           = new Date().toISOString().split('T')[0],
  } = context.vars;

  // Load fixture image, base64-encode, build data: URL
  const imagePath = path.resolve(__dirname, 'fixtures', 'receipts', fixtureImage);
  let dataUrl = '';
  if (fs.existsSync(imagePath)) {
    const imageBytes = fs.readFileSync(imagePath);
    const b64 = imageBytes.toString('base64');
    dataUrl = `data:image/png;base64,${b64}`;
  }

  // Exact system prompt from receipt-ingest.js L340-364 (without dynamic
  // merchant/item hints — those are app-scoped and irrelevant to eval).
  const systemPrompt = `You are a receipt parser for the SetAll expense-tracking app.
Extract structured data from the receipt image.

Rules:
- amount: the TOTAL amount paid (after tax, tips, discounts). Decimal string, e.g. "45.50".
- currency: 3-letter ISO code. Infer from symbol ($→USD, €→EUR, £→GBP, ₾→GEL, ₽→RUB, ¥→CNY).
  If ambiguous use defaultCurrency from context.
- description: merchant name or top item, 3-6 words, in the receipt's original language —
  do NOT translate to English.
- category: pick exactly one from knownCategories.
- merchant_name: normalized merchant/store name.
- last4: last 4 digits of the card used, if visible on receipt. null if not visible.
  NEVER guess or invent a last4. Extract only if clearly printed.
- entry_date: date from receipt in YYYY-MM-DD. If not readable use today's date from context.
- line_items: array of individual line items (name, amount, quantity). Empty array if not parseable.
  Preserve each item's name EXACTLY as printed on the receipt, in its original language and script
  (Georgian, Cyrillic, Arabic, CJK, etc.). Do NOT translate, transliterate, or reduce a name to only
  its Latin/SKU/brand fragment — keep the full descriptive text as shown, including non-Latin characters.
- confidence: your confidence 0.0–1.0 that the amount and currency are correct.
- needs_clarification: "amount" if total is unreadable, "currency" if indeterminate, "date" if
  date is critical and missing, null otherwise.

Merchant memory hints:
(none yet)

Group item hints (for group_id none):
(none yet)

Today's date: ${today}  Timezone: ${timezone}  Default currency: ${defaultCurrency}`;

  return [
    { role: 'system', content: systemPrompt },
    {
      role: 'user',
      content: [
        { type: 'image_url', image_url: { url: dataUrl, detail: 'high' } },
        { type: 'text', text: `knownCategories: ${JSON.stringify(knownCategories)}` },
      ],
    },
  ];
};
