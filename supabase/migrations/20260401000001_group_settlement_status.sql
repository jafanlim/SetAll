-- Migration: Add settlement status columns to groups table.
-- Settlement is a pure status flag (no expense entries created).
-- settled_at: ISO-8601 timestamp when the group was marked as settled (NULL = not settled).
-- settled_by: uid of the user who triggered the settlement (NULL = not settled).

ALTER TABLE groups
  ADD COLUMN IF NOT EXISTS settled_at  TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS settled_by  UUID        DEFAULT NULL REFERENCES auth.users(id);

-- Allow any group member to update settled_at / settled_by so both debtors
-- and creditors can initiate or clear a settlement.
-- The existing "group members can update groups" RLS policy covers this;
-- no additional policy is needed as long as members have UPDATE access.
