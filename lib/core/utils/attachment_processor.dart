import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path/path.dart' as p;

// Native-only imports — excluded on web to avoid MissingPluginException.
import 'dart:io' as io
    if (dart.library.html) '../stubs/io_stub.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart'
    if (dart.library.html) '../stubs/image_compress_stub.dart';
import 'package:pdfx/pdfx.dart'
    if (dart.library.html) '../stubs/pdfx_stub.dart';

/// Result of processing a local attachment file before upload.
class ProcessedAttachment {
  const ProcessedAttachment({this.bytes, this.storedFilename, this.textContent});

  /// Compressed WebP bytes to upload to Supabase Storage.
  final Uint8List? bytes;

  /// Filename for storage (always .webp for media/PDF, null for text-only).
  final String? storedFilename;

  /// For .txt / .md: the file content to save to the notes field.
  /// When set, no upload is performed.
  final String? textContent;

  bool get isTextOnly => textContent != null;
}

/// On-device processing before upload:
///   • Images  → resize to ≤1200px (longest side), convert to WebP 80%, strip EXIF
///   • PDFs    → render page 1, convert to WebP 80% ≤1200px
///   • .txt/.md → read content (caller saves to notes field; file is NOT uploaded)
///   • Other   → rejected (not in allowed set)
class AttachmentProcessor {
  AttachmentProcessor._();

  static const _allowed = {
    'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp', 'gif', 'raw',
    'pdf',
    'txt', 'md',
  };
  static const _imageExts = {
    'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp', 'gif', 'raw',
  };

  static String _ext(String path) => path.split('.').last.toLowerCase();

  static bool isAllowed(String path) => _allowed.contains(_ext(path));
  static bool isTextFile(String path) {
    final e = _ext(path);
    return e == 'txt' || e == 'md';
  }
  static bool isImage(String path) => _imageExts.contains(_ext(path));
  static bool isPdf(String path)   => _ext(path) == 'pdf';

  /// Process [localPath]. Returns null if the extension is not allowed or
  /// processing fails.
  static Future<ProcessedAttachment?> process(String localPath) async {
    if (kIsWeb) return null;
    final ext = _ext(localPath);
    if (!_allowed.contains(ext)) return null;

    if (ext == 'txt' || ext == 'md') {
      try {
        final content = await io.File(localPath).readAsString();
        return ProcessedAttachment(textContent: content);
      } catch (_) {
        return null;
      }
    }

    if (_imageExts.contains(ext)) return _processImage(localPath);
    if (ext == 'pdf')             return _processPdf(localPath);

    return null;
  }

  // ── Image ─────────────────────────────────────────────────────────────────
  static Future<ProcessedAttachment?> _processImage(String localPath) async {
    // Try WebP conversion first.
    try {
      final result = await FlutterImageCompress.compressWithFile(
        localPath,
        minWidth: 1200,
        minHeight: 1200,
        quality: 80,
        format: CompressFormat.webp,
        keepExif: false,
      );
      if (result != null) {
        final filename = '${p.basenameWithoutExtension(localPath)}.webp';
        return ProcessedAttachment(bytes: result, storedFilename: filename);
      }
      debugPrint('[AttachmentProcessor] WebP returned null, trying JPEG fallback');
    } catch (e) {
      debugPrint('[AttachmentProcessor] WebP compression failed: $e — trying JPEG fallback');
    }

    // JPEG fallback (e.g. macOS platform limits).
    try {
      final result = await FlutterImageCompress.compressWithFile(
        localPath,
        minWidth: 1200,
        minHeight: 1200,
        quality: 80,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (result != null) {
        final filename = '${p.basenameWithoutExtension(localPath)}.jpg';
        return ProcessedAttachment(bytes: result, storedFilename: filename);
      }
      debugPrint('[AttachmentProcessor] JPEG fallback also returned null, using raw bytes');
    } catch (e) {
      debugPrint('[AttachmentProcessor] JPEG fallback failed: $e — using raw bytes');
    }

    // Last resort: upload original bytes unchanged.
    try {
      final bytes = await io.File(localPath).readAsBytes();
      return ProcessedAttachment(bytes: bytes, storedFilename: p.basename(localPath));
    } catch (e) {
      debugPrint('[AttachmentProcessor] raw read failed: $e');
      return null;
    }
  }

  // ── PDF page 1 ────────────────────────────────────────────────────────────
  static Future<ProcessedAttachment?> _processPdf(String localPath) async {
    PdfDocument? doc;
    PdfPage? page;
    try {
      doc  = await PdfDocument.openFile(localPath);
      if (doc.pagesCount == 0) return null;
      page = await doc.getPage(1);

      // Scale so the longest side is ≤1200px.
      final scale    = 1200.0 / (page.width > page.height ? page.width : page.height);
      final renderW  = (page.width  * scale).clamp(1.0, 1200.0);
      final renderH  = (page.height * scale).clamp(1.0, 1200.0);

      final img = await page.render(
        width:  renderW,
        height: renderH,
        format: PdfPageImageFormat.png,
      );
      if (img == null) return null;

      final pngBytes = img.bytes;
      final webp = await FlutterImageCompress.compressWithList(
        pngBytes,
        minWidth: 1200,
        minHeight: 1200,
        quality: 80,
        format: CompressFormat.webp,
      );
      final filename = '${p.basenameWithoutExtension(localPath)}_p1.webp';
      return ProcessedAttachment(bytes: webp, storedFilename: filename);
    } catch (_) {
      return null;
    } finally {
      await page?.close();
      await doc?.close();
    }
  }
}
