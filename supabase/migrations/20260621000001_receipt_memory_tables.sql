create table public.payment_methods (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  last4            text not null check (last4 ~ '^[0-9]{4}$'),
  label            text not null,
  owner_profile_id uuid references public.profiles(id) on delete set null,
  created_at       timestamptz not null default now(),
  constraint payment_methods_user_last4_unique unique(user_id, last4)
);
alter table public.payment_methods enable row level security;
create policy "users manage own payment_methods" on public.payment_methods
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create table public.merchant_memory (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  merchant_name text not null,
  category      text not null,
  hit_count     int  not null default 1 check (hit_count > 0),
  last_seen_at  timestamptz not null default now(),
  constraint merchant_memory_user_merchant_unique unique(user_id, merchant_name)
);
alter table public.merchant_memory enable row level security;
create policy "users manage own merchant_memory" on public.merchant_memory
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create table public.item_memory (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  item_name    text not null,
  category     text not null,
  hit_count    int  not null default 1 check (hit_count > 0),
  last_seen_at timestamptz not null default now(),
  constraint item_memory_group_item_unique unique(group_id, item_name)
);
alter table public.item_memory enable row level security;
create policy "group members read/write item_memory" on public.item_memory
  for all using (public.is_group_member(group_id)) with check (public.is_group_member(group_id));
