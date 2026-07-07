/// Where the runtime writes its diagnostics (library loading, engine
/// creation timing, captured native stderr). Injectable replacement for the
/// original client's `debugPrint` — a pure Dart package must not assume a
/// Flutter console.
typedef LogSink = void Function(String message);

/// Default sink: standard output.
void stdoutLogSink(String message) {
  // ignore: avoid_print — this IS the console sink.
  print(message);
}

/// Sink that drops everything.
void silentLogSink(String message) {}
