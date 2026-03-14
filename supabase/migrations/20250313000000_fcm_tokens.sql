-- FCM token storage for push notifications
-- Each user may have multiple devices; upserted on login per device.

create table if not exists public.fcm_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  token       text not null,
  platform    text not null check (platform in ('android', 'ios', 'macos', 'web', 'windows')),
  updated_at  timestamptz not null default now(),
  constraint fcm_tokens_user_token_unique unique (user_id, token)
);

-- Index for fast per-user lookups (e.g. fan-out notifications)
create index if not exists fcm_tokens_user_id_idx on public.fcm_tokens(user_id);

-- RLS: users can only read/write their own tokens
alter table public.fcm_tokens enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'fcm_tokens'
      and policyname = 'Users manage own FCM tokens'
  ) then
    execute 'create policy "Users manage own FCM tokens"
      on public.fcm_tokens for all
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id)';
  end if;
end $$;

-- Auto-update updated_at on upsert
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists fcm_tokens_updated_at on public.fcm_tokens;
create trigger fcm_tokens_updated_at
  before update on public.fcm_tokens
  for each row execute function public.set_updated_at();
