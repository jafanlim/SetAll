// Stub for flutter_image_compress on web.
// Selected by the conditional import when dart.library.html is available.

// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:typed_data';

enum CompressFormat { webp, jpeg, png, heic }

class FlutterImageCompress {
  static Future<Uint8List?> compressWithFile(
    String path, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) async => null;

  static Future<Uint8List?> compressWithList(
    Uint8List list, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) async => null;
}
