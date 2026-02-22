-- SetAll: splits table (who owes how much per expense)

create table if not exists public.splits (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount_owed numeric(14, 4) not null check (amount_owed >= 0),
  created_at timestamptz not null default now(),
  unique (expense_id, user_id)
);

create index if not exists idx_splits_expense_id on public.splits(expense_id);
create index if not exists idx_splits_user_id on public.splits(user_id);

alter table public.splits enable row level security;

create policy "Group members can read splits for their group expenses"
  on public.splits for select
  using (
    expense_id in (
      select id from public.expenses
      where group_id in (select public.get_my_groups())
    )
  );

create policy "Expense payer can manage splits"
  on public.splits for all
  using (
    expense_id in (
      select id from public.expenses where payer_id = auth.uid()
    )
  );

comment on table public.splits is 'Per-user share of an expense (amount owed)';
