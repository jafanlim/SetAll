-- =============================================================================
-- SetAll: Full schema for Supabase — run this once in SQL Editor
-- Dashboard → SQL Editor → New query → paste → Run
-- =============================================================================

-- 1. PROFILES (extends auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  default_currency text not null default 'USD',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can read all profiles"
  on public.profiles for select using (true);

create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert with check (auth.uid() = id);

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', 'User'));
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

comment on table public.profiles is 'User profiles with display name and default currency';

-- 2. GROUPS & GROUP_MEMBERS
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  creator_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_groups_creator_id on public.groups(creator_id);
alter table public.groups enable row level security;

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists idx_group_members_user_id on public.group_members(user_id);
alter table public.group_members enable row level security;

create policy "Users can read groups they belong to"
  on public.groups for select
  using (
    id in (select group_id from public.group_members where user_id = auth.uid())
    or creator_id = auth.uid()
  );

create policy "Authenticated users can create groups"
  on public.groups for insert with check (auth.uid() = creator_id);

create policy "Creator can update group"
  on public.groups for update using (creator_id = auth.uid());

create policy "Creator can delete group"
  on public.groups for delete using (creator_id = auth.uid());

create policy "Members can read group_members"
  on public.group_members for select
  using (
    group_id in (select group_id from public.group_members where user_id = auth.uid())
    or group_id in (select id from public.groups where creator_id = auth.uid())
  );

create policy "Group creator can manage members"
  on public.group_members for all
  using (group_id in (select id from public.groups where creator_id = auth.uid()));

comment on table public.groups is 'Cost-sharing groups';
comment on table public.group_members is 'Group membership';

-- 3. EXPENSES (with category and currency normalization)
do $$ begin
  create type public.split_type as enum ('even', 'manual', 'parts');
exception
  when duplicate_object then null;
end $$;

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  payer_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(14, 4) not null check (amount >= 0),
  description text not null default '',
  currency text not null default 'USD',
  split_type public.split_type not null default 'even',
  category text default 'General',
  original_amount numeric(14, 4),
  original_currency text,
  exchange_rate_applied numeric(14, 6),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Add columns if table already existed without them
alter table public.expenses add column if not exists category text default 'General';
alter table public.expenses add column if not exists original_amount numeric(14, 4);
alter table public.expenses add column if not exists original_currency text;
alter table public.expenses add column if not exists exchange_rate_applied numeric(14, 6);

create index if not exists idx_expenses_group_id on public.expenses(group_id);
create index if not exists idx_expenses_payer_id on public.expenses(payer_id);
create index if not exists idx_expenses_created_at on public.expenses(created_at desc);

alter table public.expenses enable row level security;

create policy "Group members can read expenses"
  on public.expenses for select
  using (
    group_id in (select group_id from public.group_members where user_id = auth.uid())
    or group_id in (select id from public.groups where creator_id = auth.uid())
  );

create policy "Group members can insert expenses"
  on public.expenses for insert
  with check (
    auth.uid() = payer_id
    and (
      group_id in (select group_id from public.group_members where user_id = auth.uid())
      or group_id in (select id from public.groups where creator_id = auth.uid())
    )
  );

create policy "Payer or group creator can update expense"
  on public.expenses for update
  using (payer_id = auth.uid() or group_id in (select id from public.groups where creator_id = auth.uid()));

create policy "Payer or group creator can delete expense"
  on public.expenses for delete
  using (payer_id = auth.uid() or group_id in (select id from public.groups where creator_id = auth.uid()));

comment on table public.expenses is 'Expenses per group with amount, currency, split type, and optional currency normalization';

-- 4. SPLITS
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
      select e.id from public.expenses e
      where e.group_id in (select group_id from public.group_members where user_id = auth.uid())
         or e.group_id in (select id from public.groups where creator_id = auth.uid())
    )
  );

create policy "Expense payer can manage splits"
  on public.splits for all
  using (expense_id in (select id from public.expenses where payer_id = auth.uid()));

comment on table public.splits is 'Per-user share of an expense (amount owed)';

-- 5. RPC: add member by email
create or replace function public.add_member_by_email(p_group_id uuid, p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if p_email is null or trim(p_email) = '' then
    raise exception 'Email is required';
  end if;
  if not exists (select 1 from public.groups where id = p_group_id and creator_id = auth.uid()) then
    raise exception 'Only the group creator can add members';
  end if;
  select id into v_user_id from auth.users where email = trim(lower(p_email)) limit 1;
  if v_user_id is null then
    raise exception 'No user found with this email';
  end if;
  insert into public.group_members (group_id, user_id)
  values (p_group_id, v_user_id)
  on conflict (group_id, user_id) do nothing;
end;
$$;

comment on function public.add_member_by_email is 'Add a member to a group by email; caller must be group creator';
grant execute on function public.add_member_by_email(uuid, text) to authenticated;
grant execute on function public.add_member_by_email(uuid, text) to anon;

-- 6. Helper: is current user a member of the group?
create or replace function public.is_group_member(p_group_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from public.group_members where group_id = p_group_id and user_id = auth.uid())
  or exists (select 1 from public.groups where id = p_group_id and creator_id = auth.uid());
$$;

comment on function public.is_group_member(uuid) is 'True if auth.uid() is a member or creator of the group';
grant execute on function public.is_group_member(uuid) to authenticated;
grant execute on function public.is_group_member(uuid) to anon;

-- Done. SetAll schema is ready.
