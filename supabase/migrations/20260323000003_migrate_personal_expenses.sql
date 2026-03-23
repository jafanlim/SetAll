INSERT INTO public.wallet_entries (
  id, user_id, amount, is_income, description, category,
  currency, original_amount, original_currency, exchange_rate_applied,
  universal_usd_amount, icon_codepoint, icon_color, notes, attachment_urls,
  created_at, updated_at
)
SELECT e.id, e.payer_id, e.amount, COALESCE(e.is_income, false),
  e.description, COALESCE(e.category, 'Other'), e.currency,
  e.original_amount, e.original_currency, e.exchange_rate_applied,
  COALESCE(e.universal_usd_amount, 0),
  e.icon_codepoint, e.icon_color, e.notes, e.attachment_urls,
  e.created_at, e.updated_at
FROM public.expenses e
JOIN auth.users u ON u.id = e.payer_id
WHERE e.group_id IS NULL
ON CONFLICT (id) DO NOTHING;
