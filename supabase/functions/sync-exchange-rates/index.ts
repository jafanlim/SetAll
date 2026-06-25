/**
 * SetAll – sync-exchange-rates Edge Function
 *
 * Scheduled: every 24 hours via Supabase Cron (pg_cron) or external CRON.
 * Source: Fawaz Ahmed's free currency API (no key required, ~170 currencies).
 * Upserts all USD-based rates into the exchange_rates table.
 *
 * Invoke manually (for testing):
 *   curl -X POST https://<project>.supabase.co/functions/v1/sync-exchange-rates \
 *        -H "Authorization: Bearer <service_role_key>"
 *
 * Schedule with pg_cron (run once in Supabase SQL editor):
 *   SELECT cron.schedule(
 *     'sync-exchange-rates',
 *     '0 6 * * *',  -- 06:00 UTC daily
 *     $$
 *       SELECT net.http_post(
 *         url := 'https://<project>.supabase.co/functions/v1/sync-exchange-rates',
 *         headers := '{"Authorization": "Bearer <service_role_key>"}'::jsonb
 *       );
 *     $$
 *   );
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}')['default']!;

// Fawaz Ahmed currency API – free, no key, ~170 currencies, updated daily.
// Docs: https://github.com/fawazahmed0/exchange-api
const RATES_URL =
  'https://cdn.jsdelivr.net/npm/@fawaz06/currency-api@latest/v1/currencies/usd.min.json';

// Fallback mirror if primary CDN is down
const RATES_URL_FALLBACK =
  'https://latest.currency-api.pages.dev/v1/currencies/usd.min.json';

interface RateRecord {
  base_currency: string;
  target_currency: string;
  rate: number;
  last_updated: string;
}

Deno.serve(async (_req: Request): Promise<Response> => {
  try {
    // --- Fetch rates from primary source, fallback if needed ---
    let data: Record<string, Record<string, number>> | null = null;
    for (const url of [RATES_URL, RATES_URL_FALLBACK]) {
      try {
        const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
        if (res.ok) {
          data = await res.json();
          break;
        }
      } catch (_) {
        // try next URL
      }
    }
    if (!data || !data.usd) {
      throw new Error('All rate API sources failed');
    }

    const usdRates = data.usd as Record<string, number>;
    const now = new Date().toISOString();

    const rows: RateRecord[] = Object.entries(usdRates)
      .filter(([, rate]) => typeof rate === 'number' && rate > 0)
      .map(([target, rate]) => ({
        base_currency: 'USD',
        target_currency: target.toUpperCase(),
        rate,
        last_updated: now,
      }));

    // --- Upsert into Supabase in batches of 200 ---
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const BATCH = 200;
    let upserted = 0;

    for (let i = 0; i < rows.length; i += BATCH) {
      const chunk = rows.slice(i, i + BATCH);
      const { error } = await supabase
        .from('exchange_rates')
        .upsert(chunk, { onConflict: 'base_currency,target_currency' });
      if (error) throw new Error(`Supabase upsert error: ${error.message}`);
      upserted += chunk.length;
    }

    return new Response(
      JSON.stringify({ ok: true, currencies_synced: upserted, synced_at: now }),
      { headers: { 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('[sync-exchange-rates]', err);
    return new Response(
      JSON.stringify({ ok: false, error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
});
