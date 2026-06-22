#!/usr/bin/env node
// Manual end-to-end test for the receipt-ingest Netlify function.
// Privacy-aligned: sends a LOCAL image inline as base64 — nothing is uploaded/stored.
//
// Required env vars (anon key is public/client-side; password is yours — never commit):
//   SUPABASE_ANON_KEY   your project's anon key
//   TEST_EMAIL          a real SetAll user's email
//   TEST_PASSWORD       that user's password
// Optional:
//   FN_URL    defaults to the receipt-ingest-test preview
//   IMG       path to a local receipt image (jpg/png/webp). Defaults to ./sample-receipt.jpg
//
// Run:
//   SUPABASE_ANON_KEY=... TEST_EMAIL=... TEST_PASSWORD=... IMG=~/Desktop/receipt.jpg \
//     node scripts/test-receipt-ingest.mjs

import { readFileSync } from 'node:fs';

const SUPABASE_URL = 'https://vrsmsgyxeyzyrdonsnrk.supabase.co';
const ANON   = process.env.SUPABASE_ANON_KEY;
const EMAIL  = process.env.TEST_EMAIL;
const PASS   = process.env.TEST_PASSWORD;
const FN_URL = process.env.FN_URL
  || 'https://receipt-ingest-test--setall.netlify.app/.netlify/functions/receipt-ingest';
const IMG    = process.env.IMG || './sample-receipt.jpg';

if (!ANON || !EMAIL || !PASS) {
  console.error('Missing env: set SUPABASE_ANON_KEY, TEST_EMAIL, TEST_PASSWORD');
  process.exit(1);
}

const ext = IMG.split('.').pop().toLowerCase();
const contentType = ext === 'png' ? 'image/png'
  : ext === 'webp' ? 'image/webp'
  : 'image/jpeg';

// 1) Mint a user JWT via password grant.
const authRes = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
  method: 'POST',
  headers: { apikey: ANON, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: EMAIL, password: PASS }),
});
const auth = await authRes.json();
if (!auth.access_token) {
  console.error('Auth failed:', auth);
  process.exit(1);
}
console.log('✓ got JWT for', EMAIL);

// 2) Base64 the local image (nothing is uploaded).
const imageBase64 = readFileSync(IMG.replace(/^~/, process.env.HOME)).toString('base64');
console.log(`✓ read ${IMG} (${Math.round(imageBase64.length / 1024)} KB base64)`);

// 3) Call the function.
const t0 = Date.now();
const res = await fetch(FN_URL, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${auth.access_token}`,
  },
  body: JSON.stringify({
    imageBase64,
    contentType,
    groupId: null,
    defaultCurrency: 'GEL',
    timezone: 'Asia/Tbilisi',
  }),
});
const text = await res.text();
console.log(`\nHTTP ${res.status}  (${Date.now() - t0} ms)`);
try { console.log(JSON.stringify(JSON.parse(text), null, 2)); }
catch { console.log(text); }
