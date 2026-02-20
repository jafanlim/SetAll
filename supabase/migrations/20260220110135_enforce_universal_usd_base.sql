ALTER TABLE public.expenses RENAME COLUMN base_amount_at_entry TO universal_usd_amount;
ALTER TABLE public.splits RENAME COLUMN amount_owed TO universal_usd_owed;y