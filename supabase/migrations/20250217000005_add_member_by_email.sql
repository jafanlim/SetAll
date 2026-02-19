-- RPC: add a member to a group by email (caller must be group creator).
-- Resolves email via auth.users (security definer).

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
  -- Caller must be creator of the group
  if not exists (
    select 1 from public.groups
    where id = p_group_id and creator_id = auth.uid()
  ) then
    raise exception 'Only the group creator can add members';
  end if;
  -- Resolve user by email (auth.users)
  select id into v_user_id
  from auth.users
  where email = trim(lower(p_email))
  limit 1;
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
