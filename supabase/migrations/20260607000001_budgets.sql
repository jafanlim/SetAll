create table public.budgets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  category    text,                        -- null = overall budget
  period      text not null default 'monthly',
  amount      numeric not null,
  currency    text not null,               -- stored in user's base currency
  created_at  timestamptz default now()
);

alter table public.budgets enable row level security;

create policy "budgets_select" on public.budgets
  for select using (auth.uid() = user_id);

create policy "budgets_insert" on public.budgets
  for insert with check (auth.uid() = user_id);

create policy "budgets_update" on public.budgets
  for update using (auth.uid() = user_id);

create policy "budgets_delete" on public.budgets
  for delete using (auth.uid() = user_id);
