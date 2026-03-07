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
  static const int _version = 10;

  /// True when running on web (no SQLite); app uses Supabase only.
  static bool get isWeb => _webMode;

  /// Call from main when kIsWeb so repo uses Supabase-only without opening SQLite.
  static void setWebMode() {
    _webMode = true;
    _instance ??= LocalDatabase._();
  }

  static Future<LocalDatabase> get instance async {
    _instance ??= LocalDatabase._();
    if (_db == null && !_webMode) {
      try {
        _db = await _instance!._open();
      } catch (_) {
        _webMode = true;
      }
    }
    return _instance!;
  }

  static Database get db {
    if (_db != null) return _db!;
    throw StateError(
      'LocalDatabase not initialized or web mode (use Supabase only).',
    );
  }

  static Database? get dbOrNull => _db;

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
      // True Wallet: personal expenses now use group_id = NULL.
      // SQLite doesn't support ALTER COLUMN, so we recreate the expenses table
      // without the NOT NULL constraint on group_id.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS expenses_new (
          id                   TEXT PRIMARY KEY,
          group_id             TEXT,
          payer_id             TEXT NOT NULL,
          created_by           TEXT,
          amount               TEXT NOT NULL,
          total_amount         TEXT,
          description          TEXT,
          currency             TEXT,
          split_type           TEXT,
          category             TEXT,
          original_amount      TEXT,
          original_currency    TEXT,
          exchange_rate_applied TEXT,
          universal_usd_amount TEXT,
          created_at           TEXT,
          updated_at           TEXT,
          synced_at            INTEGER
        )
      ''');
      await db.execute('INSERT INTO expenses_new SELECT * FROM expenses');
      await db.execute('DROP TABLE expenses');
      await db.execute('ALTER TABLE expenses_new RENAME TO expenses');
      // Smart user categories table.
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
        id         TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        creator_id TEXT NOT NULL,
        created_by TEXT, -- Schema v7
        type       TEXT NOT NULL DEFAULT 'normal',
        created_at TEXT,
        updated_at TEXT,
        synced_at  INTEGER
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
        id                   TEXT PRIMARY KEY,
        group_id             TEXT,
        payer_id             TEXT NOT NULL,
        created_by           TEXT, -- Schema v7
        amount               TEXT NOT NULL,
        total_amount         TEXT, -- Schema v7
        description          TEXT,
        currency             TEXT,
        split_type           TEXT,
        category             TEXT,
        original_amount      TEXT,
        original_currency    TEXT,
        exchange_rate_applied TEXT,
        universal_usd_amount TEXT, -- Schema v8
        created_at           TEXT,
        updated_at           TEXT,
        synced_at            INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE splits (
        id                 TEXT PRIMARY KEY,
        expense_id         TEXT NOT NULL,
        user_id            TEXT NOT NULL,
        universal_usd_owed TEXT NOT NULL, -- Schema v8
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
  }
}

