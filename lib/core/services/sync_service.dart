import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
  RealtimeChannel? _channel;

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
  /// Safe to call at any time — no-ops when offline, on web, or if already
  /// running. The [_isSyncing] flag prevents "sync storms" when many realtime
  /// events arrive simultaneously.
  Future<void> performFullSync() async {
    if (_isSyncing) return;
    if (_isWeb || _client == null) return;
    if (!await _isOnline) return;
    final uid = await _repo.ensureUser();
    if (uid == null) return;

    _isSyncing = true;
    try {
      try {
        await _pushPendingToSupabase(uid);
      } catch (e) {
        debugPrint('[SyncService] push error: $e');
      }

      try {
        await _pullFromSupabase(uid);
        _repo.notifySyncComplete();
      } catch (e) {
        debugPrint('[SyncService] pull error: $e');
      }
    } finally {
      _isSyncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Realtime: Supabase → local (cross-device push)
  // ---------------------------------------------------------------------------

  /// Subscribes to Postgres changes for all sync-relevant tables.
  /// When a remote change is detected that the current user didn't author,
  /// a full sync is triggered automatically.
  ///
  /// Safe to call multiple times — cancels any existing channel first.
  void subscribeToRealtime() {
    if (_isWeb || _client == null) return;
    unsubscribeFromRealtime();

    void onRemoteChange(PostgresChangePayload payload) {
      // Fire-and-forget: errors are swallowed inside performFullSync.
      performFullSync();
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
        });
  }

  /// Removes the realtime channel and releases the websocket subscription.
  void unsubscribeFromRealtime() {
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
      try {
        await _client.from('groups').insert({
          'id': row['id'],
          'name': row['name'],
          'creator_id': row['creator_id'],
          'type': row['type'] ?? 'normal',
        });
        await LocalDatabase.db.update(
          'groups',
          {'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        await _client.from('group_members').insert({
          'group_id': row['id'],
          'user_id': row['creator_id'],
        });
        await LocalDatabase.db.update(
          'group_members',
          {'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'group_id = ?',
          whereArgs: [row['id']],
        );
      } catch (_) {}
    }

    final pendingExpenses =
        await LocalDatabase.db.query('expenses', where: 'synced_at IS NULL');
    for (final row in pendingExpenses) {
      try {
        final expense = ExpenseModel.fromJson(row);
        // Strip local-only / schema-mismatched fields before sending to Supabase.
        final payload = expense.toJson()
          ..remove('created_by')
          ..remove('base_amount_at_entry');
        await _client.from('expenses').insert(payload);
        await LocalDatabase.db.update(
          'expenses',
          {'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      } catch (e) {
        if (e is PostgrestException && e.code == '23505') {
          // Duplicate key: row is already in Supabase — mark synced locally.
          debugPrint('[SyncService] expense already in cloud, marking synced: ${row['id']}');
          await LocalDatabase.db.update(
            'expenses',
            {'synced_at': DateTime.now().millisecondsSinceEpoch},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } else {
          // Any other error (RLS, network, bad data): leave synced_at=null
          // so this row is retried on the next sync cycle.
          debugPrint('[SyncService] expense push failed, will retry: $e');
        }
      }
    }

    // Only push splits whose parent expense is already confirmed in Supabase.
    // If the expense push failed, the split will also fail with a 42501 RLS
    // error because Supabase can't find a matching expense row.
    final pendingSplits = await LocalDatabase.db.rawQuery('''
      SELECT s.* FROM splits s
      INNER JOIN expenses e ON s.expense_id = e.id
      WHERE s.synced_at IS NULL AND e.synced_at IS NOT NULL
    ''');
    for (final row in pendingSplits) {
      try {
        final split = SplitModel.fromJson(row);
        await _client.from('splits').insert(split.toJson());
        await LocalDatabase.db.update(
          'splits',
          {'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      } catch (e) {
        if (e is PostgrestException && e.code == '23505') {
          // Duplicate key: already in Supabase — mark synced.
          await LocalDatabase.db.update(
            'splits',
            {'synced_at': DateTime.now().millisecondsSinceEpoch},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } else {
          debugPrint('[SyncService] split push failed, will retry: $e');
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Pull: Supabase → SQLite
  // ---------------------------------------------------------------------------

  Future<void> _pullFromSupabase(String uid) async {
    if (_client == null) return;

    final memberRows = await _client
        .from('group_members')
        .select('group_id')
        .eq('user_id', uid);
    final memberIds = (memberRows as List)
        .map((e) => (e as Map<String, dynamic>)['group_id'] as String)
        .toSet()
        .toList();
    final created =
        await _client.from('groups').select('id').eq('creator_id', uid);
    for (final r in created as List) {
      memberIds.add((r as Map<String, dynamic>)['id'] as String);
    }
    if (memberIds.isEmpty) return;

    final groups = await _client
        .from('groups')
        .select()
        .inFilter('id', memberIds.toList());
    for (final g in groups as List) {
      final map = g as Map<String, dynamic>;
      await LocalDatabase.db.insert(
        'groups',
        {
          'id': map['id'],
          'name': map['name'],
          'creator_id': map['creator_id'],
          'type': map['type'] ?? 'normal',
          'created_at': map['created_at']?.toString(),
          'updated_at': map['updated_at']?.toString(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
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
            'avatar_url': m['avatar_url'],
            'is_ghost': (m['is_ghost'] == true) ? 1 : 0,
            'default_currency': m['default_currency'] ?? 'USD',
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (_) {}

    final expenses = await _client
        .from('expenses')
        .select()
        .inFilter('group_id', memberIds.toList());
    for (final e in expenses as List) {
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

    final expenseIds = (expenses as List)
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
}
