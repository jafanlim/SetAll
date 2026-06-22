import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/auth_config.dart';
import '../models/receipt_ingest_result.dart';

// Native-only image compression — excluded on web to avoid MissingPluginException.
import 'package:flutter_image_compress/flutter_image_compress.dart'
    if (dart.library.html) '../stubs/image_compress_stub.dart';

/// Singleton service for receipt image ingest.
///
/// Privacy: the receipt image is NEVER uploaded or persisted server-side. It is
/// compressed on device, sent inline as base64 to the Netlify fn purely to
/// extract a draft, and discarded. The caller keeps the WebP bytes if it wants a
/// local-only cache (see Phase 4 / ReceiptCacheService).
///
/// Mirrors [VoiceEntryService] in pattern:
///   • compressReceipt — read + WebP-compress the scanned image (call once)
///   • ingest          — base64 → POST Netlify fn → parse draft
///   • writeBackMemory — best-effort Supabase upserts (merchant + item memory)
class ReceiptIngestService {
  static final ReceiptIngestService _instance = ReceiptIngestService._();
  static ReceiptIngestService get instance => _instance;
  ReceiptIngestService._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Compress the scanned receipt to WebP (≤1200px). Returns the bytes so the
  /// caller can both [ingest] them and cache them locally without recompressing.
  /// [imagePath] is a local file path (native) or blob URL (web).
  Future<Uint8List?> compressReceipt(String imagePath) => _compressImage(imagePath);

  /// Send the compressed receipt bytes to the Netlify receipt-ingest function
  /// for AI parsing. The image is sent inline (base64) and never stored.
  ///
  /// [knownCategories] should be the user's localized category list (mirror
  /// voice_entry_sheet) so the returned category matches the app language.
  /// [locale] is the app's current locale (e.g. 'en', 'es', 'ka') — the AI
  /// translates line items & description to this language while preserving
  /// originals in [LineItem.originalName] / [ReceiptDraft.originalDescription].
  ///
  /// Returns a parsed [ReceiptIngestResponse] — either a draft or a
  /// clarification request.
  Future<ReceiptIngestResponse> ingest(
    Uint8List webpBytes, {
    String? groupId,
    String defaultCurrency = 'USD',
    List<String> knownCategories = const [
      'Food & drink',
      'Transport',
      'Shopping',
      'Entertainment',
      'Bills & utilities',
      'Travel',
      'General',
      'Other',
    ],
    String timezone = 'UTC',
    String locale = 'en',
  }) async {
    if (webpBytes.isEmpty) throw Exception('Empty receipt image');

    final client = Supabase.instance.client;
    final accessToken = client.auth.currentSession?.accessToken;
    if (accessToken == null) throw Exception('Not authenticated');

    final response = await http
        .post(
          Uri.parse(AuthConfig.netlifyReceiptIngestUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'imageBase64': base64Encode(webpBytes),
            'contentType': 'image/webp',
            'groupId': groupId,
            'defaultCurrency': defaultCurrency,
            'knownCategories': knownCategories,
            'timezone': timezone,
            'locale': locale,
          }),
        )
        .timeout(const Duration(seconds: 30));

    switch (response.statusCode) {
      case 200:
        return ReceiptIngestResponse.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      case 401:
        throw Exception('Receipt ingest unauthorized');
      case 413:
        throw Exception('Receipt image too large');
      case 429:
        throw Exception('Rate limit exceeded — wait 60s');
      default:
        throw Exception('Receipt ingest failed: ${response.statusCode}');
    }
  }

  /// Write back learned merchant/item mappings to memory tables.
  ///
  /// Best-effort: catches and logs all errors, never throws.
  /// - [merchantName] + [category]: upsert into merchant_memory (per-user).
  /// - [itemName] + [category] + [groupId]: upsert into item_memory (per-group).
  Future<void> writeBackMemory({
    required String merchantName,
    required String category,
    String? groupId,
    String? itemName,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    // ── Merchant memory ──
    try {
      await _upsertMerchantMemory(client, userId, merchantName, category);
    } catch (e) {
      debugPrint('[ReceiptIngest] writeBackMemory merchant failed: $e');
    }

    // ── Item memory (group-scoped) ──
    if (groupId != null && groupId.isNotEmpty &&
        itemName != null && itemName.isNotEmpty) {
      try {
        await _upsertItemMemory(client, groupId, itemName, category);
      } catch (e) {
        debugPrint('[ReceiptIngest] writeBackMemory item failed: $e');
      }
    }
  }

  // ── Image compression ────────────────────────────────────────────────────

  Future<Uint8List?> _compressImage(String imagePath) async {
    if (kIsWeb) {
      // Web: read raw bytes — FlutterImageCompress is native-only.
      try {
        final response = await http.get(Uri.parse(imagePath));
        if (response.statusCode == 200) return response.bodyBytes;
      } catch (e) {
        debugPrint('[ReceiptIngest] web image read failed: $e');
      }
      return null;
    }

    final file = File(imagePath);
    if (!await file.exists()) return null;

    // Try WebP compression.
    try {
      final result = await FlutterImageCompress.compressWithFile(
        imagePath,
        minWidth: 1200,
        minHeight: 1200,
        quality: 80,
        format: CompressFormat.webp,
        keepExif: false,
      );
      if (result != null && result.isNotEmpty) return result;
    } catch (e) {
      debugPrint('[ReceiptIngest] WebP compression failed: $e');
    }

    // Fallback: raw bytes.
    try {
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('[ReceiptIngest] raw read failed: $e');
      return null;
    }
  }

  // ── Memory upsert helpers ─────────────────────────────────────────────────

  Future<void> _upsertMerchantMemory(
    SupabaseClient client,
    String userId,
    String merchantName,
    String category,
  ) async {
    final now = DateTime.now().toIso8601String();

    final existing = await client
        .from('merchant_memory')
        .select('hit_count')
        .eq('user_id', userId)
        .eq('merchant_name', merchantName)
        .maybeSingle();

    if (existing != null) {
      final newCount = (existing['hit_count'] as int? ?? 0) + 1;
      await client
          .from('merchant_memory')
          .update({
            'category': category,
            'hit_count': newCount,
            'last_seen_at': now,
          })
          .eq('user_id', userId)
          .eq('merchant_name', merchantName);
    } else {
      await client.from('merchant_memory').insert({
        'user_id': userId,
        'merchant_name': merchantName,
        'category': category,
        'hit_count': 1,
        'last_seen_at': now,
      });
    }
  }

  Future<void> _upsertItemMemory(
    SupabaseClient client,
    String groupId,
    String itemName,
    String category,
  ) async {
    final now = DateTime.now().toIso8601String();

    final existing = await client
        .from('item_memory')
        .select('hit_count')
        .eq('group_id', groupId)
        .eq('item_name', itemName)
        .maybeSingle();

    if (existing != null) {
      final newCount = (existing['hit_count'] as int? ?? 0) + 1;
      await client
          .from('item_memory')
          .update({
            'category': category,
            'hit_count': newCount,
            'last_seen_at': now,
          })
          .eq('group_id', groupId)
          .eq('item_name', itemName);
    } else {
      await client.from('item_memory').insert({
        'group_id': groupId,
        'item_name': itemName,
        'category': category,
        'hit_count': 1,
        'last_seen_at': now,
      });
    }
  }
}
