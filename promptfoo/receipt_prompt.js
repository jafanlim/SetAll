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
    locale          = 'en',
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

  // Mirrors prod system prompt from receipt-ingest.js (v2.1 — translate + keep original).
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
  - amount: the item price as a decimal string.
  - quantity: integer quantity (default 1).
- confidence: your confidence 0.0–1.0 that the amount and currency are correct.
- needs_clarification: "amount" if total is unreadable, "currency" if indeterminate, "date" if
  date is critical and missing, null otherwise.

Merchant memory hints:
(none yet)

Group item hints (for group_id none):
(none yet)

Today's date: ${today}  Timezone: ${timezone}  Default currency: ${defaultCurrency}  Locale: ${localeName}`;

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
