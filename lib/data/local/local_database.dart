import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite store for offline-first (mobile/desktop only). On web, open fails and we use Supabase only.
class LocalDatabase {
  LocalDatabase._();
  static LocalDatabase? _instance;
  static Database? _db;
  static bool _webMode = false;

  static const String _dbName = 'setall_local.db';
  static const int _version = 3;

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
    throw StateError('LocalDatabase not initialized or web mode (use Supabase only).');
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

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE expenses ADD COLUMN category TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE expenses ADD COLUMN original_amount TEXT');
      await db.execute('ALTER TABLE expenses ADD COLUMN original_currency TEXT');
      await db.execute('ALTER TABLE expenses ADD COLUMN exchange_rate_applied TEXT');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        creator_id TEXT NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        synced_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE group_members (
        group_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        joined_at TEXT,
        synced_at INTEGER,
        PRIMARY KEY (group_id, user_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        payer_id TEXT NOT NULL,
        amount TEXT NOT NULL,
        description TEXT,
        currency TEXT,
        split_type TEXT,
        category TEXT,
        original_amount TEXT,
        original_currency TEXT,
        exchange_rate_applied TEXT,
        created_at TEXT,
        updated_at TEXT,
        synced_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE splits (
        id TEXT PRIMARY KEY,
        expense_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        amount_owed TEXT NOT NULL,
        created_at TEXT,
        synced_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        default_currency TEXT,
        synced_at INTEGER
      )
    ''');
  }
}
