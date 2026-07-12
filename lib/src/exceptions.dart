/// Typed failures of the LiteRT-LM runtime.
///
/// Replaces the string-matched error surfacing of the original client: each
/// failure point of the pipeline gets its own type, and the failures that have
/// captured native diagnostics (library paths, absl/glog tail) carry them.
///
/// The hierarchy is `sealed`, so consumers can `switch` on it exhaustively;
/// the leaves are `final`, so the closed set can't be extended externally.
sealed class LiteRtLmException implements Exception {
  LiteRtLmException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The native libraries could not be located or dlopen'ed.
final class LibraryLoadException extends LiteRtLmException {
  LibraryLoadException(super.message, {this.attemptedPaths = const []});

  /// Every path/name the locator tried, in order — the single most useful
  /// piece of information when a consumer misconfigures library delivery.
  final List<String> attemptedPaths;

  @override
  String toString() {
    if (attemptedPaths.isEmpty) return super.toString();
    return '${super.toString()}\n  attempted: ${attemptedPaths.join(', ')}';
  }
}

/// `engine_create` failed in the native runtime.
final class EngineCreateException extends LiteRtLmException {
  EngineCreateException(super.message, {this.nativeLogTail});

  /// Tail of the redirected native stderr (absl/glog) captured around the
  /// failure, when stderr redirection is available on the platform.
  final String? nativeLogTail;

  @override
  String toString() {
    final tail = nativeLogTail;
    if (tail == null || tail.isEmpty) return super.toString();
    return '${super.toString()}\n  native log tail:\n$tail';
  }
}

/// A generation call failed after the engine was successfully created.
///
/// Carries [nativeLogTail] when available — the canonical nasty native
/// generation crash (the #318 `DYNAMIC_UPDATE_SLICE` / `executor.cc` KV-cache
/// failure) happens at generation time, not engine-create, so this is where
/// the tail matters most.
final class GenerationException extends LiteRtLmException {
  GenerationException(super.message, {this.nativeLogTail});

  /// Tail of the redirected native stderr around the generation failure, when
  /// available on the platform.
  final String? nativeLogTail;

  @override
  String toString() {
    final tail = nativeLogTail;
    if (tail == null || tail.isEmpty) return super.toString();
    return '${super.toString()}\n  native log tail:\n$tail';
  }
}

/// The engine or conversation was used after `close()`.
///
/// This signals a CALLER bug (use-after-dispose), like [StateError] — it is
/// not a recoverable runtime failure. It sits under [LiteRtLmException] for
/// uniform handling, but a `catch` that means to handle runtime failures
/// should not silently swallow it.
final class DisposedException extends LiteRtLmException {
  DisposedException(super.message);
}
