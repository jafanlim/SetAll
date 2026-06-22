import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../../data/local/local_database.dart';

/// Local-only receipt image cache — writes WebP files to
/// `getApplicationSupportDirectory()/receipt_cache/{expenseId}.webp`.
///
/// Files are purged 30 days after their last view. Call [purgeExpired] once
/// on app launch (throttled via the existing launch flow). On web this is a
/// no-op — returns null from [pathFor] and [purgeExpired] does nothing.
class ReceiptCacheService {
  static final ReceiptCacheService _instance = ReceiptCacheService._();
  static ReceiptCacheService get instance => _instance;
  ReceiptCacheService._();

  static const _dirName = 'receipt_cache';
  static const Duration _ttl = Duration(days: 30);

  /// Write [bytes] (WebP) to disk and upsert the cache row.
  /// No-op on web.
  Future<void> cache(String expenseId, List<int> bytes) async {
    if (kIsWeb || bytes.isEmpty) return;

    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) await dir.create(recursive: true);

      final file = File('${dir.path}/$expenseId.webp');
      await file.writeAsBytes(bytes);

      final db = LocalDatabase.dbOrNull;
      if (db == null) return;

      await db.insert(
        'receipt_cache',
        {
          'expense_id': expenseId,
          'path': file.path,
          'last_viewed_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: null, // use upsert via replace
      );
      // Upsert: delete then insert for cross-platform safety.
      await db.delete('receipt_cache', where: 'expense_id = ?', whereArgs: [expenseId]);
      await db.insert('receipt_cache', {
        'expense_id': expenseId,
        'path': file.path,
        'last_viewed_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[ReceiptCache] cache failed: $e');
    }
  }

  /// Returns the file path if the receipt is cached, and refreshes the
  /// last_viewed_at timestamp (viewing resets the 30-day TTL).
  /// Returns null on web, if the file is missing, or on error.
  Future<String?> pathFor(String expenseId) async {
    if (kIsWeb) return null;

    try {
      final db = LocalDatabase.dbOrNull;
      if (db == null) return null;

      final rows = await db.query(
        'receipt_cache',
        columns: ['path'],
        where: 'expense_id = ?',
        whereArgs: [expenseId],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final path = rows.first['path'] as String?;
      if (path == null) return null;

      final file = File(path);
      if (!await file.exists()) {
        // Stale row — clean up.
        await db.delete('receipt_cache', where: 'expense_id = ?', whereArgs: [expenseId]);
        return null;
      }

      // Refresh the TTL.
      await db.update(
        'receipt_cache',
        {'last_viewed_at': DateTime.now().toIso8601String()},
        where: 'expense_id = ?',
        whereArgs: [expenseId],
      );

      return path;
    } catch (e) {
      debugPrint('[ReceiptCache] pathFor failed: $e');
      return null;
    }
  }

  /// Delete rows + files where last_viewed_at < now − 30 days.
  /// Call once on app launch. No-op on web.
  Future<void> purgeExpired() async {
    if (kIsWeb) return;

    try {
      final db = LocalDatabase.dbOrNull;
      if (db == null) return;

      final cutoff = DateTime.now().subtract(_ttl).toIso8601String();

      final rows = await db.query(
        'receipt_cache',
        columns: ['expense_id', 'path'],
        where: 'last_viewed_at < ?',
        whereArgs: [cutoff],
      );

      for (final row in rows) {
        final path = row['path'] as String?;
        if (path != null) {
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      }

      await db.delete(
        'receipt_cache',
        where: 'last_viewed_at < ?',
        whereArgs: [cutoff],
      );
    } catch (e) {
      debugPrint('[ReceiptCache] purgeExpired failed: $e');
    }
  }

  Future<Directory> _cacheDir() async {
    final appDir = await getApplicationSupportDirectory();
    return Directory('${appDir.path}/$_dirName');
  }
}
