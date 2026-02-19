-- Phase 4: RLS alignment — simplification and group-scoped access.
-- Ensure simplification/privileged logic only runs when auth.uid() is a member of the group.

-- Helper: true if the current user is a member of the group (or creator).
create or replace function public.is_group_member(p_group_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = auth.uid()
  )
  or exists (
    select 1 from public.groups
    where id = p_group_id and creator_id = auth.uid()
  );
$$;

comment on function public.is_group_member(uuid) is 'True if auth.uid() is a member or creator of the group. Use in RPCs that must be group-scoped.';

grant execute on function public.is_group_member(uuid) to authenticated;
grant execute on function public.is_group_member(uuid) to anon;

-- Explicit policy: only group creator can insert into group_members (no cross-group add by non-creators).
-- Existing "Group creator can manage members" already restricts insert; this documents the constraint.
-- Optional: drop the broad "for all" and use separate insert/update/delete if you want to restrict further.
-- No change needed if current policies are sufficient.

-- Ensure expenses INSERT requires caller to be group member (payer_id = auth.uid() and member of group).
-- Existing policy already has: with check (auth.uid() = payer_id and (group_id in (select ... group_members))).
-- So we are aligned. Done.
