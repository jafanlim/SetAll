// Stub for dart:html — used on non-web platforms so download_screen.dart compiles.
// ignore_for_file: avoid_classes_with_only_static_members

class AnchorElement {
  AnchorElement({String? href});
  // ignore: unused_element
  final StyleStub style = StyleStub();
  void setAttribute(String name, String value) {}
  void click() {}
  void remove() {}
}

class StyleStub {
  String display = '';
}

class _Body {
  void append(AnchorElement anchor) {}
}

class _Document {
  final _Body? body = _Body();
}

final document = _Document();
