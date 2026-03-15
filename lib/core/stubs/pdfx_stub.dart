// Stub for pdfx on web.
// Selected by the conditional import when dart.library.html is available.

import 'dart:typed_data';

enum PdfPageImageFormat { png, jpeg, webp }

class PdfDocument {
  int get pagesCount => 0;
  static Future<PdfDocument> openFile(String path) async => PdfDocument._();
  PdfDocument._();
  Future<void> close() async {}
  Future<PdfPage> getPage(int pageNumber) async => PdfPage._();
}

class PdfPage {
  double get width => 0;
  double get height => 0;
  PdfPage._();
  Future<void> close() async {}
  Future<PdfPageImage?> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.png,
  }) async => null;
}

class PdfPageImage {
  Uint8List get bytes => Uint8List(0);
}
