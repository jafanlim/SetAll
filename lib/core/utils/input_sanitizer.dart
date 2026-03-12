/// Strips HTML tags and script-injection patterns from user-supplied text
/// before it is persisted to the database.
class InputSanitizer {
  InputSanitizer._();

  static final _scriptBlock = RegExp(
    r'<script\b[^>]*>.*?</script>',
    multiLine: true, caseSensitive: false, dotAll: true,
  );
  static final _iframeBlock = RegExp(
    r'<iframe\b[^>]*>.*?</iframe>',
    multiLine: true, caseSensitive: false, dotAll: true,
  );
  static final _htmlTag = RegExp(r'<[^>]+>', caseSensitive: false);
  static final _jsProto = RegExp(r'javascript\s*:', caseSensitive: false);
  static final _dataProto = RegExp(r'data\s*:', caseSensitive: false);

  /// Returns [input] with all HTML / injection patterns removed.
  static String sanitize(String input) => input
      .replaceAll(_scriptBlock, '')
      .replaceAll(_iframeBlock, '')
      .replaceAll(_htmlTag, '')
      .replaceAll(_jsProto, '')
      .replaceAll(_dataProto, '')
      .trim();
}
