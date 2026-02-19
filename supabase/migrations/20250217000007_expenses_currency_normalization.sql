-- Currency normalization: store original amount/currency and rate applied for correct balance in base currency.
alter table public.expenses
  add column if not exists original_amount numeric(14, 4),
  add column if not exists original_currency text,
  add column if not exists exchange_rate_applied numeric(14, 6);

comment on column public.expenses.original_amount is 'Amount as entered by user (before conversion to base)';
comment on column public.expenses.original_currency is 'Currency as entered (e.g. EUR)';
comment on column public.expenses.exchange_rate_applied is 'Rate from original_currency to base (amount column) at time of save';
