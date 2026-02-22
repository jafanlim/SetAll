-- SetAll: expenses table

create type public.split_type as enum ('even', 'manual', 'parts');

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  payer_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(14, 4) not null check (amount >= 0),
  description text not null default '',
  category text not null default 'General',
  currency text not null default 'USD',
  split_type public.split_type not null default 'even',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_expenses_group_id on public.expenses(group_id);
create index if not exists idx_expenses_payer_id on public.expenses(payer_id);
create index if not exists idx_expenses_created_at on public.expenses(created_at desc);

alter table public.expenses enable row level security;

create policy "Group members can read expenses"
  on public.expenses for select
  using (
    group_id in (select public.get_my_groups())
  );

create policy "Group members can insert expenses"
  on public.expenses for insert
  with check (
    auth.uid() = payer_id
    and group_id in (select public.get_my_groups())
  );

create policy "Payer or group creator can update expense"
  on public.expenses for update
  using (
    payer_id = auth.uid() 
    or group_id in (select id from public.groups where creator_id = auth.uid())
  );

create policy "Payer or group creator can delete expense"
  on public.expenses for delete
  using (
    payer_id = auth.uid() 
    or group_id in (select id from public.groups where creator_id = auth.uid())
  );

comment on table public.expenses is 'Expenses per group with amount, currency and split type';
