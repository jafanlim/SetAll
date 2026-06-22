create table public.recurring_rules (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  description     text not null,
  amount          numeric not null,
  currency        text not null,
  category        text,
  interval_days   integer not null,          -- detected cadence (28–32)
  last_seen_at    date not null,             -- most recent occurrence
  next_expected   date,                      -- last_seen_at + interval_days
  status          text not null default 'confirmed', -- confirmed | dismissed
  created_at      timestamptz default now()
);

alter table public.recurring_rules enable row level security;

create policy "recurring_rules_select" on public.recurring_rules
  for select using (auth.uid() = user_id);

create policy "recurring_rules_insert" on public.recurring_rules
  for insert with check (auth.uid() = user_id);

create policy "recurring_rules_update" on public.recurring_rules
  for update using (auth.uid() = user_id);

create policy "recurring_rules_delete" on public.recurring_rules
  for delete using (auth.uid() = user_id);
