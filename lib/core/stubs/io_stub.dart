// Stub for dart:io types used in update_service.dart on web.
// Selected by the conditional import when dart.library.html is available.

// ignore_for_file: avoid_classes_with_only_static_members

class Platform {
  static bool get isMacOS   => false;
  static bool get isWindows => false;
  static bool get isLinux   => false;
  static String get pathSeparator => '/';
}

class ProcessStartMode {
  static const ProcessStartMode detached = ProcessStartMode._();
  const ProcessStartMode._();
}

class Process {
  static Future<dynamic> start(
    String executable,
    List<String> arguments, {
    ProcessStartMode? mode,
    bool runInShell = false,
  }) async {}
}

class File {
  File(this.path);
  final String path;
  dynamic openWrite() => _NullSink();
  Future<String> readAsString() async => '';
  Future<List<int>> readAsBytes() async => [];
}

class _NullSink {
  void add(List<int> data) {}
  Future<void> flush() async {}
  Future<void> close() async {}
}

Never exit(int code) => throw UnsupportedError('exit() not supported on web');
