-- ai_rate_limit: per-user rate-limit window for the ai-analyst Edge Function.
-- Keyed by user_id + window_start (unix epoch truncated to 60s).
-- count is incremented atomically via upsert in the Edge Function.
-- RLS: users can only touch their own row; service_role bypasses for the upsert.
create table if not exists public.ai_rate_limit (
  user_id      uuid    not null references auth.users(id) on delete cascade,
  window_start bigint  not null,
  count        int     not null default 1,
  primary key (user_id, window_start)
);

alter table public.ai_rate_limit enable row level security;

create policy "Users can read own rate-limit row"
  on public.ai_rate_limit for select
  using (auth.uid() = user_id);

create policy "Users can insert own rate-limit row"
  on public.ai_rate_limit for insert
  with check (auth.uid() = user_id);

create policy "Users can update own rate-limit row"
  on public.ai_rate_limit for update
  using (auth.uid() = user_id);

-- Prune rows older than 5 minutes to keep the table small.
-- Called opportunistically from the Edge Function via rpc.
create or replace function public.prune_ai_rate_limit() returns void
  language sql security definer as $$
  delete from public.ai_rate_limit
  where window_start < extract(epoch from now())::bigint - 300;
$$;
