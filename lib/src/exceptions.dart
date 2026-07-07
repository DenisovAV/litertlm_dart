/// Typed failures of the LiteRT-LM runtime.
///
/// Replaces the string-matched error surfacing of the original client: each
/// failure point of the pipeline gets its own type, and engine-creation
/// failures carry the captured native-log tail (absl/glog output) that is
/// otherwise lost.
sealed class LiteRtLmException implements Exception {
  LiteRtLmException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The native libraries could not be located or dlopen'ed.
class LibraryLoadException extends LiteRtLmException {
  LibraryLoadException(super.message, {this.attemptedPaths = const []});

  /// Every path/name the locator tried, in order — the single most useful
  /// piece of information when a consumer misconfigures library delivery.
  final List<String> attemptedPaths;
}

/// `engine_create` failed in the native runtime.
class EngineCreateException extends LiteRtLmException {
  EngineCreateException(super.message, {this.nativeLogTail});

  /// Tail of the redirected native stderr (absl/glog) captured around the
  /// failure, when stderr redirection is available on the platform.
  final String? nativeLogTail;
}

/// A generation call failed after the engine was successfully created.
class GenerationException extends LiteRtLmException {
  GenerationException(super.message);
}

/// The engine or conversation was used after `close()`.
class DisposedException extends LiteRtLmException {
  DisposedException(super.message);
}
