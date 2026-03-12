-- Phase 1.2: Group Identity & Customization
-- Adds icon, colour, and avatar-photo support to the groups table.

alter table public.groups
  add column if not exists icon_name   text,
  add column if not exists color_value integer,
  add column if not exists avatar_url  text;

comment on column public.groups.icon_name   is 'Material icon name for group identity (e.g. flight_outlined)';
comment on column public.groups.color_value is 'Accent colour as ARGB integer (0xFFRRGGBB)';
comment on column public.groups.avatar_url  is 'Supabase Storage path for the group avatar photo (group-avatars bucket)';
