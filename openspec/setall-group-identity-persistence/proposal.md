# Proposal: Fix Group Icon & Colour Not Persisting ("don't stick")

Status: OPEN — not started
Owner: TBD
Related code: `lib/features/groups/presentation/screens/create_group_screen.dart` (`_create` ~L200-255),
`lib/data/repositories/setall_repository.dart` (`createGroup` L919-1036, sync diff L780-782,
`updateGroupCustomization` L1039), `lib/data/models/group_model.dart`,
Supabase RPC `create_group`, `groups` table RLS

## Why

Icons and colours chosen when creating/editing a group don't stick — they appear set, then
revert. This recurs ("still a mess"). Needs a real root-cause fix, not another patch.

## Root-Cause Analysis (strong hypothesis)

In `createGroup` (mobile path, L919-1036):

1. Local SQLite row is inserted **with** `icon_name` + `color_value`. ✅ (initial display OK)
2. Remote create uses RPC `create_group` with **only `p_name`** — the RPC never receives
   icon/colour. It returns a fresh `remoteId`.
3. Icon/colour are then patched via a **separate** `_client.from('groups').update({...})`
   wrapped in `try { ... } catch (_) {}` — **errors are silently swallowed** (L999-1007).
   - If RLS blocks a direct creator `UPDATE` on `groups` (insert is via SECURITY DEFINER RPC,
     but direct update may not be permitted), this patch fails *silently*. Remote row keeps
     `icon_name = null, color_value = null`.
4. On the next pull-sync, the server's null identity **overwrites** the local values
   (the sync diff at L780-782 compares iconName/colorValue/avatarUrl and treats server as
   source of truth) → icon/colour revert. **This is the "don't stick".**

Likely the same failure mode for `updateGroupCustomization` (L1039) if it relies on a direct
RLS-gated UPDATE.

## Proposed Approach — "remake it properly"

1. **Make identity atomic in the RPC.** Extend `create_group` to accept
   `p_icon_name, p_color_value, p_avatar_url, p_default_currency` and set them inside the
   SECURITY DEFINER function. Removes the dependency on a separate RLS-gated UPDATE.
2. **Add an RLS policy** allowing the group creator (and admins) to `UPDATE` their own
   `groups` row — needed for later edits via `updateGroupCustomization`. Or route all
   identity edits through a SECURITY DEFINER `update_group_identity` RPC.
3. **Stop swallowing errors.** Replace `catch (_) {}` with logged failures + a retry queue, so
   a failed identity write doesn't silently desync.
4. **Last-write-wins on sync, don't blindly trust server.** Use `updated_at` to decide; never
   let a server `null` overwrite a locally-set non-null identity (guard in the L780 diff).
5. **Verify the columns exist** on the `groups` table in all environments and that
   `color_value` (ARGB int) round-trips (check no int/text coercion in the RPC/migration).

## Scope

**In:** RPC signature extension, RLS/identity-update RPC, error surfacing + retry, sync
non-clobber guard, migration verification, edit-group path parity.
**Out:** redesign of the colour/icon picker UI (it works); avatar upload pipeline (separate).

## Open Questions

- RPC params vs a dedicated `update_group_identity` RPC — pick one pattern and use it for both
  create and edit.
- Does the web path (direct `groups` insert, L933-941) actually persist today, or does it hit
  the same RLS wall? Verify both platforms.

## Tasks

- [ ] Reproduce: create group with non-default icon+colour, force a sync, confirm revert
- [ ] Confirm RLS on `groups` UPDATE for creator (likely the smoking gun)
- [ ] Migration: extend `create_group` RPC to set identity atomically
- [ ] Add `update_group_identity` RPC (or creator UPDATE RLS policy)
- [ ] Repo: route create + edit through RPC; remove `catch(_){}`, add logging/retry
- [ ] Sync: guard against server-null clobbering local identity (LWW by updated_at)
- [ ] Verify web path persists too
- [ ] Tests: create/edit identity → sync round-trip keeps icon+colour
