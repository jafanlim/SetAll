-- =============================================================================
-- Fix Group Identity Persistence
-- =============================================================================
-- Root cause: color_value was integer (32-bit) — ARGB values like 0xFF14B8A6
-- exceed signed 32-bit range and the remote write fails silently. Also,
-- default_currency column didn't exist on groups, and create_group RPC only
-- accepted p_name, requiring a separate RLS-fragile direct UPDATE for identity.
--
-- Fixes:
-- 1. Widen color_value to bigint (64-bit) for ARGB round-trip.
-- 2. Add default_currency column on groups.
-- 3. Extend create_group to set identity atomically (SECURITY DEFINER).
-- 4. Add update_group_identity RPC (SECURITY DEFINER, creator-only).
-- =============================================================================

-- 1. Fix column types ---------------------------------------------------------

ALTER TABLE public.groups ALTER COLUMN color_value TYPE bigint;

ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS default_currency text;

COMMENT ON COLUMN public.groups.default_currency IS 'Default 3-letter currency code for the group (e.g. USD, EUR)';

-- 2. Replace create_group with identity-aware version -------------------------

DROP FUNCTION IF EXISTS public.create_group(text);

CREATE OR REPLACE FUNCTION public.create_group(
  p_name             text,
  p_icon_name        text   DEFAULT NULL,
  p_color_value      bigint DEFAULT NULL,
  p_avatar_url       text   DEFAULT NULL,
  p_default_currency text   DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_group_id uuid := gen_random_uuid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF trim(p_name) = '' THEN
    RAISE EXCEPTION 'group_name_empty';
  END IF;

  INSERT INTO public.groups (id, name, creator_id, type, icon_name, color_value, avatar_url, default_currency)
  VALUES (v_group_id, trim(p_name), v_uid, 'normal', p_icon_name, p_color_value, p_avatar_url, p_default_currency);

  INSERT INTO public.group_members (group_id, user_id)
  VALUES (v_group_id, v_uid)
  ON CONFLICT DO NOTHING;

  RETURN v_group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_group(text, text, bigint, text, text) TO authenticated;

COMMENT ON FUNCTION public.create_group IS
  'Creates a normal group with identity columns and adds the caller as a member. SECURITY DEFINER bypasses RLS.';

-- 3. Identity-only update RPC (creator-gated, no broad UPDATE RLS) ------------
-- NULL params mean "leave unchanged" (COALESCE). p_clear_avatar = true sets
-- avatar_url to NULL explicitly; otherwise a NULL p_avatar_url is a no-op.

DROP FUNCTION IF EXISTS public.update_group_identity(uuid, text, bigint, text, text);

CREATE OR REPLACE FUNCTION public.update_group_identity(
  p_group_id         uuid,
  p_icon_name        text    DEFAULT NULL,
  p_color_value      bigint  DEFAULT NULL,
  p_avatar_url       text    DEFAULT NULL,
  p_default_currency text    DEFAULT NULL,
  p_clear_avatar     boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid           uuid := auth.uid();
  v_creator_id    uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT creator_id INTO v_creator_id
  FROM public.groups
  WHERE id = p_group_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'group_not_found';
  END IF;

  IF v_creator_id != v_uid THEN
    RAISE EXCEPTION 'not_group_creator';
  END IF;

  UPDATE public.groups
  SET
    icon_name        = COALESCE(p_icon_name, icon_name),
    color_value      = COALESCE(p_color_value, color_value),
    avatar_url       = CASE WHEN p_clear_avatar THEN NULL
                            ELSE COALESCE(p_avatar_url, avatar_url) END,
    default_currency = COALESCE(p_default_currency, default_currency),
    updated_at       = now()
  WHERE id = p_group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_group_identity(uuid, text, bigint, text, text, boolean) TO authenticated;

COMMENT ON FUNCTION public.update_group_identity IS
  'Updates only group identity columns. NULL params leave unchanged (COALESCE). p_clear_avatar=true explicitly nulls avatar_url. SECURITY DEFINER. Only the group creator may call.';
