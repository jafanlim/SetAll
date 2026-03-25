import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, debugPrint, TargetPlatform;
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/local_database.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/split_model.dart';
import '../../data/repositories/setall_repository.dart';

/// Coordinates two-way synchronization between local SQLite and Supabase.
///
/// The Repository is now SQLite-only for reads. This service owns the entire
/// push/pull cycle and must be triggered explicitly (e.g. on app launch, on
/// pull-to-refresh, or on network reconnect).
///
/// Call [performFullSync] to run a complete push-then-pull cycle.
/// Call [subscribeToRealtime] once after sign-in to enable live cross-device sync.
/// Call [unsubscribeFromRealtime] on sign-out to release the websocket channel.
class SyncService {
  SyncService({
    required SetAllRepository repository,
    SupabaseClient? client,
  })  : _repo = repository,
        _client = client;

  final SetAllRepository _repo;
  final SupabaseClient? _client;

  bool _isSyncing = false;
  bool _syncPending = false;
  RealtimeChannel? _channel;
  Timer? _periodicTimer;
  Timer? _resubscribeTimer;
  Timer? _debounceTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool get _isWeb => LocalDatabase.isWeb;

  Future<bool> get _isOnline async {
    if (kIsWeb) return _client != null;
    try {
      final result = await Connectivity().checkConnectivity();
      return result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  /// Full sync cycle: push pending local writes, then pull remote state.
  ///
  /// Safe to call at any time — no-ops when offline or on web.
  /// If a sync is already running, sets [_syncPending] so the cycle reruns
  /// immediately after the current one finishes. This ensures no change event
  /// is ever silently dropped.
  Future<void> performFullSync() async {
    if (_isSyncing) {
      _syncPending = true;
      return;
    }
    if (_isWeb || _client == null) return;
    if (!await _isOnline) return;
    final uid = await _repo.ensureUser();
    if (uid == null) return;

    _isSyncing = true;
    _syncPending = false;
    try {
      try {
        await _pushPendingToSupabase(uid);
      } catch (e) {
        debugPrint('[SyncService] push error: $e');
      }

      try {
        await _pullFromSupabase(uid);
        _repo.notifySyncComplete();
        // FEAT-10: Write net worth to App Group UserDefaults for the iOS widget.
        await _writeWidgetData();
      } catch (e) {
        debugPrint('[SyncService] pull error: $e');
      }
    } finally {
      _isSyncing = false;
      // If an event arrived while we were syncing, run one more cycle now.
      if (_syncPending) {
        _syncPending = false;
        unawaited(performFullSync());
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Realtime: Supabase → local (cross-device push)
  // ---------------------------------------------------------------------------

  /// Starts all background sync mechanisms:
  ///  1. Supabase Realtime websocket (best-effort, fires on cloud changes).
  ///  2. Periodic timer every 30 s (reliable fallback for when Realtime
  ///     events are missed due to app backgrounding or network switches).
  ///  3. Connectivity change listener (re-syncs immediately on reconnect).
  ///
  /// Safe to call multiple times — cancels existing subscriptions first.
  void subscribeToRealtime() {
    if (_isWeb || _client == null) return;
    unsubscribeFromRealtime();

    // ── Periodic timer ──────────────────────────────────────────────────────
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      debugPrint('[SyncService] periodic sync tick');
      performFullSync();
    });

    // ── Connectivity change listener ─────────────────────────────────────────
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        debugPrint('[SyncService] connectivity restored — syncing');
        performFullSync();
      }
    });

    void onRemoteChange(PostgresChangePayload payload) {
      // FEAT-05-Ph2: Debounce concurrent Realtime events into a single sync.
      // Coalesces all row-level changes within 500ms into one performFullSync()
      // call. Prevents N parallel full-pulls when multiple group members write
      // simultaneously. 500ms is imperceptible to users but eliminates the flood.
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), performFullSync);
    }

    _channel = _client
        .channel('setall-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'expenses',
          callback: onRemoteChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'expenses',
          callback: onRemoteChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'expenses',
          callback: onRemoteChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'splits',
          callback: onRemoteChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'splits',
          callback: onRemoteChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'groups',
          callback: onRemoteChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'groups',
          callback: onRemoteChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'groups',
          callback: onRemoteChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_members',
          callback: onRemoteChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'group_members',
          callback: onRemoteChange,
        )
        .subscribe((status, [error]) {
          debugPrint('[SyncService] realtime status=$status error=$error');
          if (status == RealtimeSubscribeStatus.channelError) {
            // JWT likely expired — resubscribe after a short delay.
            _resubscribeTimer?.cancel();
            _resubscribeTimer = Timer(const Duration(seconds: 5), () {
              if (_channel != null) {
                debugPrint('[SyncService] resubscribing after channelError');
                subscribeToRealtime();
              }
            });
          }
        });
  }

  /// Cancels all background sync mechanisms.
  void unsubscribeFromRealtime() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _resubscribeTimer?.cancel();
    _resubscribeTimer = null;
    _debounceTimer?.cancel(); // FEAT-05-Ph2: cancel pending debounce on dispose
    _debounceTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    if (_channel != null) {
      _client?.removeChannel(_channel!);
      _channel = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Push: SQLite → Supabase
  // ---------------------------------------------------------------------------

  Future<void> _pushPendingToSupabase(String uid) async {
    if (_client == null) return;

    final pendingGroups =
        await LocalDatabase.db.query('groups', where: 'synced_at IS NULL');
    for (final row in pendingGroups) {
      final localId   = row['id'] as String;
      final groupName = row['name'] as String? ?? '';
      try {
        // Use SECURITY DEFINER RPC to bypass RLS — direct insert on 'groups'
        // is blocked by policy on all platforms (macOS, Windows, Android, iOS).
        final remoteId = await _client.rpc(
          'create_group',
          params: {'p_name': groupName},
        ) as String;
        final finalId = remoteId != localId ? remoteId : localId;
        // Patch identity fields the RPC doesn't set.
        final iconName   = row['icon_name']   as String?;
        final colorValue = row['color_value'] as int?;
        final avatarUrl  = row['avatar_url']  as String?;
        if (iconName != null || colorValue != null || avatarUrl != null) {
          try {
            await _client.from('groups').update({
              'icon_name':   ?iconName,
              'color_value': ?colorValue,
              'avatar_url':  ?avatarUrl,
            }).eq('id', finalId);
          } catch (_) {}
        }
        if (remoteId != localId) {
          // RPC generated a new UUID — update local rows to match.
          await LocalDatabase.db.update('groups',
              {'id': remoteId, 'synced_at': DateTime.now().millisecondsSinceEpoch},
              where: 'id = ?', whereArgs: [localId]);
          await LocalDatabase.db.update('group_members',
              {'group_id': remoteId, 'synced_at': DateTime.now().millisecondsSinceEpoch},
              where: 'group_id = ?', whereArgs: [localId]);
        } else {
          await LocalDatabase.db.update('groups',
              {'synced_at': DateTime.now().millisecondsSinceEpoch},
              where: 'id = ?', whereArgs: [localId]);
          await LocalDatabase.db.update('group_members',
              {'synced_at': DateTime.now().millisecondsSinceEpoch},
              where: 'group_id = ?', whereArgs: [localId]);
        }
      } catch (e) {
        debugPrint('[SyncService] group push failed for $localId: $e');
      }
    }

    final pendingExpenses =
        await LocalDatabase.db.query('expenses', where: 'synced_at IS NULL');
    // Skip rows created by a different user (e.g. stale rows from a previous
    // session on shared device). Upserting them under a new JWT would always
    // fail RLS (payer_id != auth.uid()) and log an infinite retry loop.
    final ownedExpenses = pendingExpenses
        .where((r) => (r['payer_id'] as String?) == uid)
        .toList();
    if (ownedExpenses.isNotEmpty) {
      // Build all payloads in memory, then push in a single batch upsert.
      final payloads = <Map<String, dynamic>>[];
      for (final row in ownedExpenses) {
        final expense = ExpenseModel.fromJson(row);
        final raw = expense.toJson()
          ..remove('created_by')
          ..remove('base_amount_at_entry');
        payloads.add(<String, dynamic>{
          ...raw,
          'is_income': expense.isIncome,
          'group_id': (raw['group_id'] as String?)?.isEmpty == true
              ? null
              : raw['group_id'],
          'icon_color': (raw['icon_color'] as int?)?.toSigned(32),
        });
      }
      try {
        debugPrint('[Sync] Starting Batch Push: ${payloads.length} expenses');
        await _client.from('expenses').upsert(payloads);
        debugPrint('[Sync] Batch Push Complete: expenses');
        // Batch-mark all synced in a single SQLite transaction.
        final now = DateTime.now().millisecondsSinceEpoch;
        await LocalDatabase.db.transaction((txn) async {
          for (final row in ownedExpenses) {
            await txn.update('expenses', {'synced_at': now},
                where: 'id = ?', whereArgs: [row['id']]);
          }
        });
      } catch (e) {
        if (e is PostgrestException && e.code == '42501') {
          debugPrint('[SyncService] RLS ERROR on expense batch, will retry: ${e.message}');
        } else {
          debugPrint('[SyncService] expense batch push failed (${payloads.length} items): $e');
        }
      }
    }

    final pendingSplits = await LocalDatabase.db.rawQuery('''
      SELECT s.* FROM splits s
      INNER JOIN expenses e ON s.expense_id = e.id
      WHERE s.synced_at IS NULL AND e.synced_at IS NOT NULL
    ''');
    if (pendingSplits.isNotEmpty) {
      final payloads = pendingSplits
          .map((row) => SplitModel.fromJson(row).toJson())
          .toList();
      try {
        debugPrint('[Sync] Starting Batch Push: ${payloads.length} splits');
        await _client.from('splits').upsert(payloads);
        debugPrint('[Sync] Batch Push Complete: splits');
        final now = DateTime.now().millisecondsSinceEpoch;
        await LocalDatabase.db.transaction((txn) async {
          for (final row in pendingSplits) {
            await txn.update('splits', {'synced_at': now},
                where: 'id = ?', whereArgs: [row['id']]);
          }
        });
      } catch (e) {
        if (e is PostgrestException && e.code == '42501') {
          debugPrint('[SyncService] RLS ERROR on split batch, will retry: ${e.message}');
        } else {
          debugPrint('[SyncService] split batch push failed (${payloads.length} items): $e');
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Pull: Supabase → SQLite
  // ---------------------------------------------------------------------------

  Future<void> _pullFromSupabase(String uid) async {
    if (_client == null) return;

    // Load the groups this user has voluntarily left so we never re-pull them.
    // Guard: table may not exist on older schema installs.
    Set<String> leftGroupIds;
    try {
      final leftRows = await LocalDatabase.db.query('left_groups', columns: ['group_id']);
      leftGroupIds = leftRows.map((r) => r['group_id'] as String).toSet();
    } catch (_) {
      leftGroupIds = {};
    }

    final memberRows = await _client
        .from('group_members')
        .select('group_id')
        .eq('user_id', uid);
    final allCloudMemberIds = (memberRows as List)
        .map((e) => (e as Map<String, dynamic>)['group_id'] as String)
        .toSet();

    // For every group in left_groups where Supabase still shows us as a member,
    // retry the group_members removal (it may have failed offline on a previous
    // delete). Also keep the left_groups row unless the group exists locally AND
    // is NOT soft-deleted — that's the only genuine stale case (e.g. the user
    // was re-added to a group they previously left voluntarily).
    if (leftGroupIds.isNotEmpty) {
      final stillMemberIds = leftGroupIds.intersection(allCloudMemberIds);
      for (final gid in stillMemberIds) {
        try {
          final rows = await LocalDatabase.db.query(
            'groups',
            columns: ['is_deleted'],
            where: 'id = ?',
            whereArgs: [gid],
          );
          // Keep if: group is absent from local DB (deleted in an older app
          // version that didn't use is_deleted) OR it is soft-deleted.
          // Only remove the left_groups row when the group exists locally and
          // is NOT soft-deleted — meaning the user was legitimately re-added.
          final keepEntry = rows.isEmpty ||
              (rows.first['is_deleted'] as int? ?? 0) == 1;
          if (keepEntry) {
            debugPrint('[SyncService] keeping left_groups for $gid '
                '(${rows.isEmpty ? "absent locally" : "soft-deleted"}); '
                'retrying Supabase group_members cleanup');
            try {
              await _client.from('group_members').delete()
                  .eq('group_id', gid).eq('user_id', uid);
              debugPrint('[SyncService] removed stale group_members row for $gid');
              // Verify the delete actually stuck by re-querying group_members.
              // Supabase may silently no-op the DELETE if an RLS policy blocks it.
              // Once confirmed gone, purge left_groups so we stop retrying.
              if (rows.isEmpty) {
                try {
                  final stillMember = await _client
                      .from('group_members')
                      .select('group_id')
                      .eq('group_id', gid)
                      .eq('user_id', uid)
                      .maybeSingle();
                  if (stillMember == null) {
                    debugPrint('[SyncService] purging left_groups for $gid '
                        '(confirmed removed from group_members)');
                    await LocalDatabase.db.delete(
                      'left_groups', where: 'group_id = ?', whereArgs: [gid]);
                    leftGroupIds.remove(gid);
                  }
                  // else: delete silently failed (RLS?); keep retrying next tick.
                } catch (_) {}
              }
            } catch (e) {
              debugPrint('[SyncService] group_members cleanup failed for $gid: $e');
            }
            continue;
          }
          debugPrint('[SyncService] removing stale left_groups for $gid '
              '(group exists locally, not deleted — user was re-added)');
          await LocalDatabase.db.delete('left_groups', where: 'group_id = ?', whereArgs: [gid]);
          leftGroupIds.remove(gid);
        } catch (_) {}
      }
    }

    final memberIds = allCloudMemberIds
        .where((id) => !leftGroupIds.contains(id))
        .toList();

    // ── Reconciler: remove local orphans ────────────────────────────────────
    // If memberIds is empty the user has no groups — wipe everything local.
    // Otherwise diff cloud vs local and delete rows that no longer exist in
    // Supabase (i.e. were deleted on another device).
    await _reconcileLocalOrphans(uid, memberIds, leftGroupIds);

    // Always pull personal (wallet) expenses regardless of group membership.
    final personalExpenses = await _client
        .from('expenses')
        .select()
        .isFilter('group_id', null)
        .eq('payer_id', uid);

    final cloudPersonalIds = <String>{};
    debugPrint('[SyncService] pull: found ${(personalExpenses as List).length} personal expenses in Supabase for uid=$uid');
    for (final e in personalExpenses as List) {
      final map = e as Map<String, dynamic>;
      final expense = ExpenseModel.fromJson(map);
      cloudPersonalIds.add(expense.id);
      debugPrint('[SyncService] pull: upsert personal expense ${expense.id} payer=${expense.payerId}');
      final insertData = <String, dynamic>{
        ...expense.toJson(),
        'updated_at': map['updated_at']?.toString(),
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      };
      // Preserve local fields that Supabase may return as null (e.g. icon or
      // attachment data not yet present on older remote rows).
      // ConflictAlgorithm.replace does DELETE+INSERT, so any column absent from
      // insertData gets wiped unless we explicitly copy it from the local row.
      if (expense.iconCodepoint == null || expense.iconColor == null ||
          expense.attachmentUrls == null || expense.notes == null) {
        final existing = await LocalDatabase.db.query(
          'expenses',
          columns: ['icon_codepoint', 'icon_color', 'attachment_urls', 'notes'],
          where: 'id = ?',
          whereArgs: [expense.id],
        );
        if (existing.isNotEmpty) {
          final loc = existing.first;
          if (expense.iconCodepoint == null && loc['icon_codepoint'] != null) {
            insertData['icon_codepoint'] = loc['icon_codepoint'];
          }
          if (expense.iconColor == null && loc['icon_color'] != null) {
            insertData['icon_color'] = loc['icon_color'];
          }
          if (expense.attachmentUrls == null && loc['attachment_urls'] != null) {
            insertData['attachment_urls'] = loc['attachment_urls'];
          }
          if (expense.notes == null && loc['notes'] != null) {
            insertData['notes'] = loc['notes'];
          }
        }
      }
      await LocalDatabase.db.insert(
        'expenses',
        insertData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // Reconcile personal expenses: prune any local synced rows that no longer
    // exist in Supabase (i.e. deleted on another device). Only touch rows that
    // have been confirmed synced — unsynced rows (synced_at IS NULL) are
    // pending push and must not be deleted.
    // Only reconcile rows confirmed in Supabase (synced_at > 0).
    // synced_at IS NULL  → pending push, never delete.
    // synced_at = -1     → (legacy sentinel) treat as pending, never delete.
    // Only reconcile personal expenses paid by the current user. Expenses paid
    // by a teammate (other payer, same group) have group_id set and are handled
    // by the group expense reconciler. Wallet expenses paid by another user
    // (synced_at IS NULL) are never touched — reconciler skips IS NULL rows.
    final localPersonalRows = await LocalDatabase.db.query(
      'expenses',
      columns: ['id', 'payer_id', 'synced_at'],
      where: 'group_id IS NULL AND synced_at > 0 AND payer_id = ?',
      whereArgs: [uid],
    );
    debugPrint('[SyncService] reconciler: ${localPersonalRows.length} local synced personal expenses, ${cloudPersonalIds.length} in cloud');
    final localPersonalIds = localPersonalRows.map((r) => r['id'] as String).toSet();
    final orphanPersonalIds = localPersonalIds.difference(cloudPersonalIds);
    if (orphanPersonalIds.isNotEmpty) {
      debugPrint('[SyncService] reconciler: pruning ${orphanPersonalIds.length} orphan personal expenses');
      final orphanList = orphanPersonalIds.toList();
      final ph = orphanList.map((_) => '?').join(',');
      await LocalDatabase.db.delete('expenses', where: 'id IN ($ph)', whereArgs: orphanList);
    }

    if (memberIds.isEmpty) return;

    // Build a set of group IDs the user has locally soft-deleted so we never
    // overwrite is_deleted=1 with a fresh Supabase pull.
    final softDeletedRows = await LocalDatabase.db.query(
      'groups', columns: ['id'], where: 'is_deleted = 1');
    final softDeletedIds = softDeletedRows.map((r) => r['id'] as String).toSet();

    final groups = await _client
        .from('groups')
        .select()
        .inFilter('id', memberIds.toList());
    for (final g in groups as List) {
      final map = g as Map<String, dynamic>;
      final gid = map['id'] as String;
      // Never restore a group the user explicitly deleted on this device.
      if (softDeletedIds.contains(gid)) continue;
      // Preserve local identity fields (icon, colour, avatar) when Supabase
      // doesn't have them yet (pre-migration groups or failed remote patch).
      final existing = await LocalDatabase.db
          .query('groups', where: 'id = ?', whereArgs: [gid]);
      final ex = existing.isNotEmpty ? existing.first : const <String, dynamic>{};
      await LocalDatabase.db.insert(
        'groups',
        {
          'id': gid,
          'name': map['name'],
          'creator_id': map['creator_id'],
          'type': map['type'] ?? 'normal',
          'created_at': map['created_at']?.toString(),
          'updated_at': map['updated_at']?.toString(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
          'is_deleted': 0,
          'icon_name':   map['icon_name']   ?? ex['icon_name'],
          'color_value': map['color_value'] ?? ex['color_value'],
          'avatar_url':  sanitizeAvatarUrl(map['avatar_url'] as String?) ?? sanitizeAvatarUrl(ex['avatar_url'] as String?),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final gMembers = await _client
        .from('group_members')
        .select()
        .inFilter('group_id', memberIds.toList());
    final allMemberUserIds = <String>{uid};
    for (final m in gMembers as List) {
      final map = m as Map<String, dynamic>;
      allMemberUserIds.add(map['user_id'] as String);
      await LocalDatabase.db.insert(
        'group_members',
        {
          'group_id': map['group_id'],
          'user_id': map['user_id'],
          'joined_at': map['joined_at']?.toString(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    try {
      final profileRows = await _client
          .from('profiles')
          .select()
          .inFilter('id', allMemberUserIds.toList()) as List;
      for (final p in profileRows) {
        final m = p as Map<String, dynamic>;
        await LocalDatabase.db.insert(
          'profiles',
          {
            'id': m['id'],
            'name': m['name'] ?? '',
            'nickname': m['nickname'],
            'avatar_url': sanitizeAvatarUrl(m['avatar_url'] as String?),
            'is_ghost': (m['is_ghost'] == true) ? 1 : 0,
            'default_currency': m['default_currency'] ?? 'USD',
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (_) {}

    final groupExpenses = await _client
        .from('expenses')
        .select()
        .inFilter('group_id', memberIds.toList());

    // personalExpenses already fetched and upserted above (before memberIds check).
    final expenses = [...(groupExpenses as List)];

    for (final e in expenses) {
      final map = e as Map<String, dynamic>;
      final expense = ExpenseModel.fromJson(map);
      await LocalDatabase.db.insert(
        'expenses',
        {
          ...expense.toJson(),
          'updated_at': map['updated_at']?.toString(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final expenseIds = expenses
        .map((e) => (e as Map<String, dynamic>)['id'] as String)
        .toList();
    if (expenseIds.isNotEmpty) {
      final splits = await _client
          .from('splits')
          .select()
          .inFilter('expense_id', expenseIds);
      for (final s in splits as List) {
        final map = s as Map<String, dynamic>;
        final split = SplitModel.fromJson(map);
        // INSERT OR REPLACE leverages the UNIQUE(expense_id, user_id) index
        // (schema v9) to upsert without pre-deleting.
        await LocalDatabase.db.insert(
          'splits',
          {
            ...split.toJson(),
            'created_at': map['created_at']?.toString(),
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Reconciler: prune local orphans not present in Supabase
  // ---------------------------------------------------------------------------

  /// Deletes local SQLite rows whose IDs are no longer in the cloud.
  ///
  /// This is the mechanism that propagates remote deletions to this device.
  /// When User A deletes a group/expense, User B's next [_pullFromSupabase]
  /// call will discover the missing IDs and prune them here.
  ///
  /// [cloudGroupIds] is the authoritative set of group IDs for [uid].
  Future<void> _reconcileLocalOrphans(
    String uid,
    List<String> cloudGroupIds,
    Set<String> leftGroupIds,
  ) async {
    // ── Groups ───────────────────────────────────────────────────────────────
    final cloudGroupIdSet = cloudGroupIds.toSet();

    // Only prune groups that have been confirmed in Supabase (synced_at NOT NULL).
    // Groups with synced_at IS NULL are pending push — don't delete them.
    // Groups with is_deleted = 1 are intentionally soft-deleted locally and
    // must not be treated as cloud orphans — they may be restored later.
    // Groups in leftGroupIds were voluntarily left — never treat as orphans;
    // their local data is kept so the user can see history.
    final syncedLocalGroups = await LocalDatabase.db.query(
      'groups',
      columns: ['id'],
      where: 'synced_at IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)');
    final syncedLocalGroupIds =
        syncedLocalGroups.map((r) => r['id'] as String).toSet();
    final orphanGroupIds = syncedLocalGroupIds
        .difference(cloudGroupIdSet)
        .difference(leftGroupIds);
    if (orphanGroupIds.isNotEmpty) {
      debugPrint('[SyncService] reconciler: pruning ${orphanGroupIds.length} orphan groups');
      final orphanList = orphanGroupIds.toList();
      final ph = orphanList.map((_) => '?').join(',');
      await LocalDatabase.db.transaction((txn) async {
        // Cascade: get expense IDs for orphan groups, delete their splits first
        final expRows = await txn.query('expenses', columns: ['id'],
            where: 'group_id IN ($ph)', whereArgs: orphanList);
        if (expRows.isNotEmpty) {
          final expIds = expRows.map((r) => r['id'] as String).toList();
          final eph = expIds.map((_) => '?').join(',');
          await txn.delete('splits', where: 'expense_id IN ($eph)', whereArgs: expIds);
        }
        await txn.delete('expenses', where: 'group_id IN ($ph)', whereArgs: orphanList);
        await txn.delete('group_members', where: 'group_id IN ($ph)', whereArgs: orphanList);
        await txn.delete('groups', where: 'id IN ($ph)', whereArgs: orphanList);
      });
    }

    if (cloudGroupIds.isEmpty) return;

    // ── Expenses ─────────────────────────────────────────────────────────────
    // Fetch the authoritative expense IDs for the user's groups from Supabase.
    try {
      final cloudExpenseRows = await _client!
          .from('expenses')
          .select('id')
          .inFilter('group_id', cloudGroupIds) as List;
      final cloudExpenseIds =
          cloudExpenseRows.map((r) => (r as Map<String, dynamic>)['id'] as String).toSet();

      // Only reconcile expenses that have been synced — unsynced rows
      // (synced_at IS NULL) are pending push and must not be pruned.
      // Exclude personal (wallet) expenses: group_id IS NULL means they are
      // never in cloudGroupIds, so they must never be treated as orphans.
      // Exclude expenses belonging to soft-deleted groups (is_deleted = 1) —
      // those were intentionally moved to deleted_expenses and should not be
      // purged from live tables by the reconciler.
      final softDeletedGroupRows = await LocalDatabase.db.query(
        'groups', columns: ['id'],
        where: 'is_deleted = 1');
      final softDeletedGroupIds =
          softDeletedGroupRows.map((r) => r['id'] as String).toSet();
      final localExpenses = await LocalDatabase.db.query(
        'expenses',
        columns: ['id', 'group_id'],
        where: 'synced_at IS NOT NULL AND group_id IS NOT NULL',
      );
      // Set difference: find local expense IDs not in cloud (excluding soft-deleted groups)
      final localExpenseIds = localExpenses
          .where((row) {
            final gid = row['group_id'] as String?;
            return gid == null || !softDeletedGroupIds.contains(gid);
          })
          .map((row) => row['id'] as String)
          .toSet();
      final orphanExpenseIds = localExpenseIds.difference(cloudExpenseIds);
      if (orphanExpenseIds.isNotEmpty) {
        debugPrint('[SyncService] reconciler: pruning ${orphanExpenseIds.length} orphan expenses');
        final orphanList = orphanExpenseIds.toList();
        final ph = orphanList.map((_) => '?').join(',');
        await LocalDatabase.db.transaction((txn) async {
          await txn.delete('splits', where: 'expense_id IN ($ph)', whereArgs: orphanList);
          await txn.delete('expenses', where: 'id IN ($ph)', whereArgs: orphanList);
        });
      }

      // ── Splits ─────────────────────────────────────────────────────────────
      // Set difference: find local split IDs not in cloud.
      if (cloudExpenseIds.isNotEmpty) {
        final cloudSplitRows = await _client
            .from('splits')
            .select('id')
            .inFilter('expense_id', cloudExpenseIds.toList()) as List;
        final cloudSplitIds =
            cloudSplitRows.map((r) => (r as Map<String, dynamic>)['id'] as String).toSet();

        final localSplits = await LocalDatabase.db.query(
          'splits', columns: ['id'], where: 'synced_at IS NOT NULL');
        final localSplitIds = localSplits.map((r) => r['id'] as String).toSet();
        final orphanSplitIds = localSplitIds.difference(cloudSplitIds);
        if (orphanSplitIds.isNotEmpty) {
          debugPrint('[SyncService] reconciler: pruning ${orphanSplitIds.length} orphan splits');
          final orphanList = orphanSplitIds.toList();
          final ph = orphanList.map((_) => '?').join(',');
          await LocalDatabase.db.delete('splits', where: 'id IN ($ph)', whereArgs: orphanList);
        }
      }
    } catch (e) {
      debugPrint('[SyncService] reconciler error (non-fatal): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // FEAT-10: iOS Home Screen Widget — write net worth to shared UserDefaults
  // ---------------------------------------------------------------------------

  /// Writes the current net worth to the App Group NSUserDefaults suite so the
  /// iOS WidgetKit extension can read it. Uses SharedPreferencesAsync with
  /// appGroupId on iOS/macOS to target the correct suite; falls back to
  /// default SharedPreferences on Android.
  /// This is best-effort — never blocks or fails a sync on error.
  Future<void> _writeWidgetData() async {
    if (kIsWeb) return;
    try {
      final profile = await _repo.getCurrentUserProfile();
      final currency = profile?.defaultCurrency ?? 'USD';
      final walletNet = await _repo.getWalletOnlyBalance(baseCurrency: currency);

      final walletEntries = await _repo.getWalletEntries();
      var income  = 0.0;
      var expense = 0.0;
      for (final e in walletEntries) {
        final amt = double.tryParse(e.universalUsdAmount) ?? 0;
        if (e.isIncome) { income += amt; } else { expense += amt; }
      }

      // Group balances (best-effort — ignore if unavailable)
      double sharedOwed = 0;
      double sharedOwe  = 0;
      try {
        final summary = await _repo.getBalanceSummary();
        sharedOwed = double.tryParse(summary.youAreOwed) ?? 0;
        sharedOwe  = double.tryParse(summary.youOwe)     ?? 0;
      } catch (_) {}
      final trueNetWorth = walletNet.toDouble() + sharedOwed - sharedOwe;

      const appGroup = 'group.com.jafa.setall.app.widget';
      final isApple = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);

      if (isApple) {
        final widgetPrefs = SharedPreferencesAsync(
          options: SharedPreferencesAsyncFoundationOptions(suiteName: appGroup),
        );
        await widgetPrefs.setDouble('widget_net_worth',    walletNet.toDouble());
        await widgetPrefs.setDouble('widget_true_net',     trueNetWorth);
        await widgetPrefs.setDouble('widget_shared_owed',  sharedOwed);
        await widgetPrefs.setDouble('widget_shared_owe',   sharedOwe);
        await widgetPrefs.setDouble('widget_income',       income);
        await widgetPrefs.setDouble('widget_expenses',     expense);
        await widgetPrefs.setString('widget_currency',     currency);
        await widgetPrefs.setString('widget_updated',      DateTime.now().toIso8601String());
        final recent = walletEntries.take(3).toList();
        for (int i = 0; i < 3; i++) {
          final e = i < recent.length ? recent[i] : null;
          await widgetPrefs.setString('widget_entry_${i + 1}_desc',   e?.description ?? '');
          await widgetPrefs.setDouble('widget_entry_${i + 1}_amount', e != null ? (double.tryParse(e.universalUsdAmount) ?? 0) : 0);
          await widgetPrefs.setBool(  'widget_entry_${i + 1}_income', e?.isIncome ?? false);
        }
        debugPrint('[SyncService] widget data written: $currency wallet=$walletNet true=$trueNetWorth owed=$sharedOwed owe=$sharedOwe → $appGroup');
        try { await HomeWidget.updateWidget(iOSName: 'SetAllWidget'); }
        catch (_) { /* not available in this build config */ }
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('widget_net_worth',   walletNet.toDouble());
        await prefs.setDouble('widget_true_net',    trueNetWorth);
        await prefs.setDouble('widget_shared_owed', sharedOwed);
        await prefs.setDouble('widget_shared_owe',  sharedOwe);
        await prefs.setDouble('widget_income',      income);
        await prefs.setDouble('widget_expenses',    expense);
        await prefs.setString('widget_currency',    currency);
        await prefs.setString('widget_updated',     DateTime.now().toIso8601String());
      }
    } catch (e, st) {
      // Widget data is best-effort — never block sync on failure.
      debugPrint('[SyncService] _writeWidgetData error: $e\n$st');
    }
  }
}
