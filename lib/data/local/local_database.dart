import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite store for offline-first (mobile/desktop only). On web, open
/// fails and we use Supabase only.
class LocalDatabase {
  LocalDatabase._();
  static LocalDatabase? _instance;
  static Database? _db;
  static bool _webMode = false;
  static Future<LocalDatabase>? _initFuture;

  static const String _dbName = 'setall_local.db';

  /// Schema v4 adds:
  ///   • expenses.base_amount_at_entry – frozen base-currency total at entry time
  ///   • exchange_rates table – local mirror of Supabase exchange_rates
  /// Schema v5 adds:
  ///   • groups.type – 'normal' | 'direct' to distinguish friend vs group expenses
  /// Schema v8 adds:
  ///   • expenses.universal_usd_amount – final check for column existence
  ///   • splits.universal_usd_owed – final check for column existence
  /// Schema v9 adds:
  ///   • splits UNIQUE(expense_id, user_id) – prevents duplicate split rows
  ///     caused by local/Supabase UUID mismatch during sync
  /// Schema v10 adds:
  ///   • expenses.group_id made nullable (True Wallet: personal expenses use NULL)
  ///   • user_categories table for smart custom categories
  /// Schema v11 fixes:
  ///   • Re-runs the v10 expenses table rebuild with base_amount_at_entry included
  ///     so the SELECT * migration no longer fails for users upgrading from v4-v9.
  ///   • Adds 'left_group_ids' table to persist groups the user has voluntarily left.
  /// Schema v12 fixes:
  ///   • Adds is_income column safely via ALTER TABLE (guaranteed even if rebuild
  ///     in v11 failed silently on this device).
  ///   • Ensures left_groups table exists.
  ///   • Re-attempts full expenses rebuild using PRAGMA-based column detection.
  /// Schema v13 adds:
  ///   • groups.is_deleted – soft-delete flag (INTEGER 0/1)
  ///   • groups.deleted_at – timestamp of deletion
  /// Schema v14 adds:
  ///   • deleted_expenses – snapshot table for expense deletion audit log
  /// Schema v15 adds:
  ///   • expense_edits – audit log of expense description/category/amount changes
  /// Schema v16 fixes:
  ///   • Re-applies groups.is_deleted and groups.deleted_at safely via
  ///     _addColumnIfNotExists, guaranteeing the columns exist on any device
  ///     that skipped the original v13 migration due to the ordering bug.
  /// Schema v17 adds:
  ///   • deleted_groups_log – persists group-deletion audit events across
  ///     restarts (replaces the in-memory _pendingDeletedGroups list).
  /// Schema v18 adds:
  ///   • deleted_expenses.deleted_with_group_id – non-null when an expense was
  ///     cascade-deleted as part of a group soft-delete. Used to restore those
  ///     expenses when the group itself is restored.
  ///   • deleted_splits – snapshot of splits removed during a group soft-delete
  ///     so they can be re-inserted when the group is restored.
  /// Schema v19 adds:
  ///   • deleted_expenses.original_amount – preserves the raw entered amount
  ///     (e.g. 15000 VND) separate from the USD anchor so restore shows the
  ///     correct original value instead of the converted USD amount.
  ///   • deleted_groups_log – backfill for fresh installs that missed v17.
  /// Schema v20 adds:
  ///   • expenses.icon_codepoint – integer codepoint of the entry icon (IconData)
  ///   • expenses.icon_color    – integer ARGB value of the entry accent colour
  /// Schema v21 adds:
  ///   • expenses.attachment_urls – JSON array of Supabase Storage paths
  /// Schema v22 adds:
  ///   • expenses.notes – long-form notes; also receives .txt/.md file content
  /// Schema v23 adds:
  ///   • groups.icon_name  – Material icon name for group identity
  ///   • groups.color_value – ARGB integer accent colour
  ///   • groups.avatar_url  – Supabase Storage path for group avatar photo
  /// Schema v24 adds:
  ///   • splits.entry_amount_owed – per-person amount in the expense's entry
  ///     currency (e.g. GEL), stored alongside universal_usd_owed so the
  ///     breakdown display never needs a lossy USD back-conversion.
  /// Schema v25 adds:
  ///   • groups.default_currency – ISO 4217 code for the group's settlement currency
  /// Schema v29 adds:
  ///   • deleted_wallet_entries – snapshot table for wallet entry deletion audit log
  /// Schema v30 adds:
  ///   • deleted_wallet_entries.deleted_by – uid of the user who deleted the entry
  ///     (required so restoreWalletEntry can verify ownership)
  /// Schema v31 adds:
  ///   • ai_chat_messages.user_id – retroactive fix for devices whose _onCreate
  ///     pre-dated the v27 migration that added the column
  static const int _version = 31;

  /// True when running on web (no SQLite); app uses Supabase only.
  static bool get isWeb => _webMode;

  /// Call from main when kIsWeb so repo uses Supabase-only without opening SQLite.
  static void setWebMode() {
    _webMode = true;
    _instance ??= LocalDatabase._();
  }

  static Future<LocalDatabase> get instance {
    _instance ??= LocalDatabase._();
    if (_webMode) return Future.value(_instance!);
    _initFuture ??= _instance!._init();
    return _initFuture!;
  }

  Future<LocalDatabase> _init() async {
    if (_db == null && !_webMode) {
      try {
        _db = await _open();
      } catch (_) {
        _webMode = true;
      }
    }
    return this;
  }

  static Database get db {
    if (_db != null) return _db!;
    throw StateError(
      'LocalDatabase not initialized or web mode (use Supabase only).',
    );
  }

  static Database? get dbOrNull => _db;

  /// Injects a pre-built [Database] for unit tests. Bypasses [_open] so tests
  /// can supply an in-memory SQLite database without touching the filesystem
  /// or [path_provider]. Must be called before any repository method.
  // ignore: invalid_use_of_visible_for_testing_member
  static void injectForTesting(Database testDb) {
    _db = testDb;
    _webMode = false;
    _instance ??= LocalDatabase._();
    _initFuture = Future.value(_instance!);
  }

  /// Resets all static singleton state between tests.
  // ignore: invalid_use_of_visible_for_testing_member
  static void resetForTesting() {
    _db = null;
    _instance = null;
    _initFuture = null;
    _webMode = false;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, _dbName);
    return openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE expenses ADD COLUMN category TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE expenses ADD COLUMN original_amount TEXT');
      await db.execute('ALTER TABLE expenses ADD COLUMN original_currency TEXT');
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN exchange_rate_applied TEXT',
      );
    }
    if (oldVersion < 4) {
      // Frozen base-currency total: immutable once written, fixes the $104 bug
      // for all new expenses regardless of offline/rate-drift scenarios.
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN base_amount_at_entry TEXT',
      );
      // Local mirror of Supabase exchange_rates (populated by CurrencySyncService)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS exchange_rates (
          base_currency   TEXT NOT NULL,
          target_currency TEXT NOT NULL,
          rate            TEXT NOT NULL,
          last_updated    TEXT,
          PRIMARY KEY (base_currency, target_currency)
        )
      ''');
    }
    if (oldVersion < 5) {
      // Group type: 'normal' for shared groups, 'direct' for 1-on-1 friend expenses.
      await db.execute(
        "ALTER TABLE groups ADD COLUMN type TEXT NOT NULL DEFAULT 'normal'",
      );
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE profiles ADD COLUMN nickname TEXT');
      await db.execute('ALTER TABLE profiles ADD COLUMN avatar_url TEXT');
      await db.execute(
        'ALTER TABLE profiles ADD COLUMN is_ghost INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 7) {
      // Supabase sync alignment
      await _addColumnIfNotExists(db, 'expenses', 'created_by', 'TEXT');
      await _addColumnIfNotExists(db, 'expenses', 'total_amount', 'TEXT');
      await _addColumnIfNotExists(db, 'groups', 'created_by', 'TEXT');
    }
    if (oldVersion < 8) {
      // The "numerical illiteracy" pivot columns
      await _addColumnIfNotExists(db, 'expenses', 'universal_usd_amount', 'TEXT');
      await _addColumnIfNotExists(db, 'splits', 'universal_usd_owed', 'TEXT');
    }
    if (oldVersion < 9) {
      // Deduplicate splits rows: keep only the row with the largest rowid
      // (most recently inserted) for each (expense_id, user_id) pair.
      await db.execute('''
        DELETE FROM splits
        WHERE rowid NOT IN (
          SELECT MAX(rowid) FROM splits GROUP BY expense_id, user_id
        )
      ''');
      // Add unique index to prevent future duplicates.
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_splits_unique_pair ON splits(expense_id, user_id)',
      );
    }
    if (oldVersion < 10) {
      // Smart user categories table (safe to create even if v10 expenses
      // rebuild below already created it — IF NOT EXISTS guards it).
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_categories (
          id         TEXT PRIMARY KEY,
          name       TEXT NOT NULL,
          type       TEXT NOT NULL DEFAULT 'expense',
          created_by TEXT NOT NULL,
          created_at TEXT
        )
      ''');
    }
    if (oldVersion < 12) {
      // Phase 1: Safe ALTER TABLE additions — these cannot fail and guarantee
      // the columns exist regardless of what happened in v10/v11.
      await _addColumnIfNotExists(db, 'expenses', 'is_income',            'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'expenses', 'group_id',             'TEXT');
      await _addColumnIfNotExists(db, 'expenses', 'base_amount_at_entry', 'TEXT');
      await _addColumnIfNotExists(db, 'expenses', 'total_amount',         'TEXT');
      await _addColumnIfNotExists(db, 'expenses', 'universal_usd_amount', 'TEXT');
      await _addColumnIfNotExists(db, 'expenses', 'updated_at',           'TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS left_groups (
          group_id TEXT PRIMARY KEY,
          left_at  TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_categories (
          id         TEXT PRIMARY KEY,
          name       TEXT NOT NULL,
          type       TEXT NOT NULL DEFAULT 'expense',
          created_by TEXT NOT NULL,
          created_at TEXT
        )
      ''');

      // Phase 2: Rebuild expenses table so group_id has no NOT NULL constraint.
      // PRAGMA table_info detects which columns actually exist after Phase 1
      // so the copy never references a missing column.
      const desiredColumns = [
        'id', 'group_id', 'payer_id', 'created_by', 'amount', 'total_amount',
        'base_amount_at_entry', 'is_income', 'description', 'currency',
        'split_type', 'category', 'original_amount', 'original_currency',
        'exchange_rate_applied', 'universal_usd_amount', 'created_at',
        'updated_at', 'synced_at',
      ];
      final pragmaRows = await db.rawQuery('PRAGMA table_info(expenses)');
      final existingCols = pragmaRows.map((r) => r['name'] as String).toSet();
      final colsToCopy =
          desiredColumns.where((c) => existingCols.contains(c)).toList();
      final colList = colsToCopy.join(', ');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS expenses_v12 (
          id                    TEXT PRIMARY KEY,
          group_id              TEXT,
          payer_id              TEXT NOT NULL,
          created_by            TEXT,
          amount                TEXT NOT NULL,
          total_amount          TEXT,
          base_amount_at_entry  TEXT,
          is_income             INTEGER NOT NULL DEFAULT 0,
          description           TEXT,
          currency              TEXT,
          split_type            TEXT,
          category              TEXT,
          original_amount       TEXT,
          original_currency     TEXT,
          exchange_rate_applied TEXT,
          universal_usd_amount  TEXT,
          created_at            TEXT,
          updated_at            TEXT,
          synced_at             INTEGER
        )
      ''');
      await db.execute(
        'INSERT OR IGNORE INTO expenses_v12 ($colList) SELECT $colList FROM expenses',
      );
      await db.execute('DROP TABLE IF EXISTS expenses');
      await db.execute('ALTER TABLE expenses_v12 RENAME TO expenses');
      // Restore splits unique index (may have been lost through prior rebuilds).
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_splits_unique_pair ON splits(expense_id, user_id)',
      );
    }
    if (oldVersion < 13) {
      await _addColumnIfNotExists(db, 'groups', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'groups', 'deleted_at', 'TEXT');
    }
    if (oldVersion < 14) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS deleted_expenses (
          expense_id   TEXT PRIMARY KEY,
          description  TEXT,
          amount       TEXT NOT NULL,
          currency     TEXT,
          group_id     TEXT,
          group_name   TEXT,
          is_income    INTEGER NOT NULL DEFAULT 0,
          category     TEXT,
          deleted_by   TEXT NOT NULL,
          deleted_by_name TEXT,
          deleted_at   TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 15) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS expense_edits (
          id             TEXT PRIMARY KEY,
          expense_id     TEXT NOT NULL,
          old_description TEXT,
          new_description TEXT,
          old_category   TEXT,
          new_category   TEXT,
          old_amount     TEXT,
          new_amount     TEXT,
          currency       TEXT,
          group_id       TEXT,
          group_name     TEXT,
          edited_by      TEXT NOT NULL,
          edited_by_name TEXT,
          edited_at      TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 16) {
      // Re-apply groups.is_deleted + deleted_at defensively — devices that had
      // the migration ordering bug (v13 ran after v15) never got these columns.
      await _addColumnIfNotExists(db, 'groups', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'groups', 'deleted_at', 'TEXT');
    }
    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS deleted_groups_log (
          group_id       TEXT PRIMARY KEY,
          group_name     TEXT NOT NULL,
          creator_id     TEXT NOT NULL,
          deleted_by_uid TEXT NOT NULL,
          deleted_at     TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 18) {
      await _addColumnIfNotExists(
        db, 'deleted_expenses', 'deleted_with_group_id', 'TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS deleted_splits (
          id                   TEXT PRIMARY KEY,
          expense_id           TEXT NOT NULL,
          user_id              TEXT NOT NULL,
          amount_owed          TEXT,
          universal_usd_owed   TEXT,
          deleted_with_group_id TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 19) {
      await _addColumnIfNotExists(
        db, 'deleted_expenses', 'original_amount', 'TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS deleted_groups_log (
          group_id       TEXT PRIMARY KEY,
          group_name     TEXT NOT NULL,
          creator_id     TEXT NOT NULL,
          deleted_by_uid TEXT NOT NULL,
          deleted_at     TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 20) {
      await _addColumnIfNotExists(db, 'expenses', 'icon_codepoint', 'INTEGER');
      await _addColumnIfNotExists(db, 'expenses', 'icon_color',     'INTEGER');
    }
    if (oldVersion < 21) {
      await _addColumnIfNotExists(db, 'expenses', 'attachment_urls', 'TEXT');
    }
    if (oldVersion < 22) {
      await _addColumnIfNotExists(db, 'expenses', 'notes', 'TEXT');
    }
    if (oldVersion < 23) {
      await _addColumnIfNotExists(db, 'groups', 'icon_name',   'TEXT');
      await _addColumnIfNotExists(db, 'groups', 'color_value', 'INTEGER');
      await _addColumnIfNotExists(db, 'groups', 'avatar_url',  'TEXT');
    }
    if (oldVersion < 24) {
      await _addColumnIfNotExists(db, 'splits', 'entry_amount_owed', 'TEXT');
    }
    if (oldVersion < 25) {
      await _addColumnIfNotExists(db, 'groups', 'default_currency', 'TEXT');
    }
    if (oldVersion < 26) {
      // Schema v26: AI chat history for InsightsPanel (FEAT-06)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_chat_messages (
          id         TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          role       TEXT NOT NULL,
          content    TEXT NOT NULL,
          created_at TEXT NOT NULL,
          is_canvas  INTEGER DEFAULT 0
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ai_chat_session ON ai_chat_messages(session_id)',
      );
    }
    if (oldVersion < 27) {
      // Schema v27: AI chat isolated per user (BUG-01)
      await _addColumnIfNotExists(db, 'ai_chat_messages', 'user_id', 'TEXT');
    }
    if (oldVersion < 28) {
      // Schema v28: wallet_entries — dedicated personal finance ledger
      await db.execute('''
        CREATE TABLE IF NOT EXISTS wallet_entries (
          id                    TEXT PRIMARY KEY,
          user_id               TEXT NOT NULL,
          amount                TEXT NOT NULL,
          is_income             INTEGER NOT NULL DEFAULT 0,
          description           TEXT NOT NULL DEFAULT '',
          category              TEXT DEFAULT 'Other',
          currency              TEXT NOT NULL DEFAULT 'USD',
          original_amount       TEXT,
          original_currency     TEXT,
          exchange_rate_applied TEXT,
          universal_usd_amount  TEXT NOT NULL DEFAULT '0',
          icon_codepoint        INTEGER,
          icon_color            INTEGER,
          notes                 TEXT,
          attachment_urls       TEXT,
          deleted_at            TEXT,
          created_at            TEXT,
          updated_at            TEXT,
          synced_at             INTEGER
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_wallet_entries_user_created '
        'ON wallet_entries(user_id, created_at)',
      );
    }
    if (oldVersion < 29) {
      // Schema v29: deleted_wallet_entries — snapshot for activity feed deletion events
      await db.execute('''
        CREATE TABLE IF NOT EXISTS deleted_wallet_entries (
          entry_id    TEXT PRIMARY KEY,
          description TEXT,
          amount      TEXT NOT NULL,
          currency    TEXT,
          is_income   INTEGER NOT NULL DEFAULT 0,
          category    TEXT,
          deleted_at  TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 30) {
      // Schema v30: add deleted_by to deleted_wallet_entries
      await _addColumnIfNotExists(db, 'deleted_wallet_entries', 'deleted_by', 'TEXT');
    }
    if (oldVersion < 31) {
      // Schema v31: retroactive guard — devices whose _onCreate ran before v27
      // created ai_chat_messages without user_id. _addColumnIfNotExists is safe
      // to call even if the column already exists.
      await _addColumnIfNotExists(db, 'ai_chat_messages', 'user_id', 'TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ai_chat_user ON ai_chat_messages(user_id)',
      );
    }
  }

  /// Helper to safely add columns during migration.
  static Future<void> _addColumnIfNotExists(
    Database db,
    String tableName,
    String columnName,
    String columnType,
  ) async {
    try {
      final columns = await db.rawQuery('PRAGMA table_info($tableName)');
      final exists = columns.any((c) => c['name'] == columnName);
      if (!exists) {
        await db.execute('ALTER TABLE $tableName ADD COLUMN $columnName $columnType');
      }
    } catch (_) {}
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE groups (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        creator_id  TEXT NOT NULL,
        created_by  TEXT,           -- Schema v7
        type        TEXT NOT NULL DEFAULT 'normal',
        is_deleted  INTEGER NOT NULL DEFAULT 0, -- Schema v13
        deleted_at  TEXT,                       -- Schema v13
        icon_name        TEXT,    -- Schema v23
        color_value      INTEGER, -- Schema v23
        avatar_url       TEXT,    -- Schema v23
        default_currency TEXT,    -- Schema v25
        created_at  TEXT,
        updated_at  TEXT,
        synced_at   INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE group_members (
        group_id  TEXT NOT NULL,
        user_id   TEXT NOT NULL,
        joined_at TEXT,
        synced_at INTEGER,
        PRIMARY KEY (group_id, user_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE expenses (
        id                    TEXT PRIMARY KEY,
        group_id              TEXT,
        payer_id              TEXT NOT NULL,
        created_by            TEXT,
        amount                TEXT NOT NULL,
        total_amount          TEXT,
        base_amount_at_entry  TEXT,
        is_income             INTEGER NOT NULL DEFAULT 0,
        description           TEXT,
        currency              TEXT,
        split_type            TEXT,
        category              TEXT,
        original_amount       TEXT,
        original_currency     TEXT,
        exchange_rate_applied TEXT,
        universal_usd_amount  TEXT,
        created_at            TEXT,
        updated_at            TEXT,
        synced_at             INTEGER,
        icon_codepoint        INTEGER,
        icon_color            INTEGER,
        attachment_urls       TEXT,
        notes                 TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE splits (
        id                 TEXT PRIMARY KEY,
        expense_id         TEXT NOT NULL,
        user_id            TEXT NOT NULL,
        universal_usd_owed TEXT NOT NULL, -- Schema v8
        entry_amount_owed  TEXT,          -- Schema v24: amount in expense's entry currency
        created_at         TEXT,
        synced_at          INTEGER,
        UNIQUE(expense_id, user_id) -- Schema v9
      )
    ''');
    await db.execute('''
      CREATE TABLE profiles (
        id               TEXT PRIMARY KEY,
        name             TEXT NOT NULL,
        nickname         TEXT,
        avatar_url       TEXT,
        is_ghost         INTEGER NOT NULL DEFAULT 0,
        default_currency TEXT,
        synced_at        INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE exchange_rates (
        base_currency   TEXT NOT NULL,
        target_currency TEXT NOT NULL,
        rate            TEXT NOT NULL,
        last_updated    TEXT,
        PRIMARY KEY (base_currency, target_currency)
      )
    ''');
    await db.execute('''
      CREATE TABLE user_categories (
        id         TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        type       TEXT NOT NULL DEFAULT 'expense',
        created_by TEXT NOT NULL,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE left_groups (
        group_id TEXT PRIMARY KEY,
        left_at  TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE expense_edits (
        id             TEXT PRIMARY KEY,
        expense_id     TEXT NOT NULL,
        old_description TEXT,
        new_description TEXT,
        old_category   TEXT,
        new_category   TEXT,
        old_amount     TEXT,
        new_amount     TEXT,
        currency       TEXT,
        group_id       TEXT,
        group_name     TEXT,
        edited_by      TEXT NOT NULL,
        edited_by_name TEXT,
        edited_at      TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE deleted_groups_log (
        group_id       TEXT PRIMARY KEY,
        group_name     TEXT NOT NULL,
        creator_id     TEXT NOT NULL,
        deleted_by_uid TEXT NOT NULL,
        deleted_at     TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE deleted_expenses (
        expense_id            TEXT PRIMARY KEY,
        description           TEXT,
        amount                TEXT NOT NULL,
        original_amount       TEXT,
        currency              TEXT,
        group_id              TEXT,
        group_name            TEXT,
        is_income             INTEGER NOT NULL DEFAULT 0,
        category              TEXT,
        deleted_by            TEXT NOT NULL,
        deleted_by_name       TEXT,
        deleted_at            TEXT NOT NULL,
        deleted_with_group_id TEXT        -- Schema v18: set when cascade-deleted with a group
      )
    ''');
    await db.execute('''
      CREATE TABLE ai_chat_messages (
        id         TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role       TEXT NOT NULL,
        content    TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_canvas  INTEGER DEFAULT 0,
        user_id    TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_chat_session ON ai_chat_messages(session_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_chat_user ON ai_chat_messages(user_id)',
    );
    await db.execute('''
      CREATE TABLE deleted_splits (
        id                    TEXT PRIMARY KEY,
        expense_id            TEXT NOT NULL,
        user_id               TEXT NOT NULL,
        amount_owed           TEXT,
        universal_usd_owed    TEXT,
        deleted_with_group_id TEXT NOT NULL  -- Schema v18
      )
    ''');
    await db.execute('''
      CREATE TABLE wallet_entries (
        id                    TEXT PRIMARY KEY,
        user_id               TEXT NOT NULL,
        amount                TEXT NOT NULL,
        is_income             INTEGER NOT NULL DEFAULT 0,
        description           TEXT NOT NULL DEFAULT '',
        category              TEXT DEFAULT 'Other',
        currency              TEXT NOT NULL DEFAULT 'USD',
        original_amount       TEXT,
        original_currency     TEXT,
        exchange_rate_applied TEXT,
        universal_usd_amount  TEXT NOT NULL DEFAULT '0',
        icon_codepoint        INTEGER,
        icon_color            INTEGER,
        notes                 TEXT,
        attachment_urls       TEXT,
        deleted_at            TEXT,
        created_at            TEXT,
        updated_at            TEXT,
        synced_at             INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_wallet_entries_user_created '
      'ON wallet_entries(user_id, created_at)',
    );
  }
}

