-- SetAll: groups table

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  creator_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_groups_creator_id on public.groups(creator_id);

alter table public.groups enable row level security;

-- Members: who is in the group (for RLS and listing)
create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists idx_group_members_user_id on public.group_members(user_id);

alter table public.group_members enable row level security;

-- Policies: members can read their groups
create policy "Users can read groups they belong to"
  on public.groups for select
  using (
    id in (select group_id from public.group_members where user_id = auth.uid())
    or creator_id = auth.uid()
  );

create policy "Authenticated users can create groups"
  on public.groups for insert
  with check (auth.uid() = creator_id);

create policy "Creator can update group"
  on public.groups for update
  using (creator_id = auth.uid());

create policy "Creator can delete group"
  on public.groups for delete
  using (creator_id = auth.uid());

create policy "Members can read group_members"
  on public.group_members for select
  using (
    group_id in (select group_id from public.group_members where user_id = auth.uid())
    or group_id in (select id from public.groups where creator_id = auth.uid())
  );

create policy "Group creator can manage members"
  on public.group_members for all
  using (
    group_id in (select id from public.groups where creator_id = auth.uid())
  );

comment on table public.groups is 'Cost-sharing groups';
comment on table public.group_members is 'Group membership';
