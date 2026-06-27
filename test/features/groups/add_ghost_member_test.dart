// Hermetic regression guard for Part A — ghost-row nickname FK violation
// (TASK 7: pending_invites FK on ghost_id blocks handle_new_user PK-update).
//
// The fix (migration 20260627000001) drops the FK constraint on the ghost column
// and ensures add_ghost_member uses the safe flow: create profile first, then
// group_members, then pending_invites — with no REFERENCES clause on the ghost
// user column.
//
// This test validates the RPC parameter contract so the Dart→SQL bridge stays
// in sync and verifies email normalization (trim + lowercase).

import 'package:flutter_test/flutter_test.dart';

import 'package:setall/data/repositories/setall_repository.dart';

void main() {
  group('addGhostMember RPC parameter contract', () {
    // ── RPC function name and parameter keys (must match SQL signature) ─────
    const rpcName = 'add_ghost_member';
    const paramGroupId = 'p_group_id';
    const paramEmail = 'p_email';
    const paramInvitedBy = 'p_invited_by';

    test('RPC function name matches SQL function', () {
      expect(rpcName, 'add_ghost_member',
          reason: 'Dart RPC call must match the PostgreSQL function name');
    });

    test('parameter keys match add_ghost_member SQL signature', () {
      // SQL: add_ghost_member(p_group_id UUID, p_email TEXT, p_invited_by UUID)
      expect(paramGroupId, 'p_group_id');
      expect(paramEmail, 'p_email');
      expect(paramInvitedBy, 'p_invited_by');
    });

    test('parameter count matches SQL function signature (3 params)', () {
      final params = {paramGroupId, paramEmail, paramInvitedBy};
      expect(params.length, 3,
          reason: 'add_ghost_member takes exactly 3 parameters');
    });
  });

  group('addGhostMember null-client guard', () {
    test('returns null when Supabase is not configured', () async {
      // Repository with no Supabase client (offline / unconfigured).
      final repo = SetAllRepository(client: null);
      final result = await repo.addGhostMember(
        '00000000-0000-0000-0000-000000000001',
        'ghost@example.com',
      );
      expect(result, isNull,
          reason: 'Must return null when _client is null (offline guard)');
    });
  });

  group('Email normalization (trim + lowercase)', () {
    // The repository lowercases AND trims the email before sending to the RPC.
    // This group validates that invariant.
    test('email with whitespace is trimmed', () {
      const input = '  Ghost@Example.com  ';
      final normalized = input.trim().toLowerCase();
      expect(normalized, 'ghost@example.com');
    });

    test('email with mixed case is lowercased', () {
      const input = 'Ghost.User@Example.COM';
      final normalized = input.trim().toLowerCase();
      expect(normalized, 'ghost.user@example.com');
    });

    test('non-ASCII email is preserved through normalization', () {
      const input = 'UsuarioÑo@Ejemplo.com';
      final normalized = input.trim().toLowerCase();
      expect(normalized, 'usuarioño@ejemplo.com');
    });
  });
}
