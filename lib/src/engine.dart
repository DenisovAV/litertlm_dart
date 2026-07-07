import 'backend.dart';
import 'conversation.dart';
import 'library_locator.dart';
import 'log_sink.dart';

/// Entry point of the package.
abstract final class LiteRtLm {
  /// Loads the native runtime (if not yet loaded) and creates an engine for
  /// the `.litertlm` model at [modelPath].
  ///
  /// [maxTokens] is the CONTEXT window (input + output, KV-cache budget) and
  /// is clamped up to the model's baked `kv_cache_max_len` — see the
  /// flutter_gemma #318 postmortem; to cap the RESPONSE length use
  /// [Engine.createConversation]'s `maxOutputTokens`.
  ///
  /// [androidNativeLibDir] is required only for [Backend.npu] on Android
  /// (the QNN dispatch libs live in the app's nativeLibraryDir; a Flutter
  /// adapter obtains it via a platform channel and passes it down).
  static Future<Engine> createEngine({
    required String modelPath,
    Backend backend = Backend.cpu,
    Backend? visionBackend,
    int maxTokens = 2048,
    bool vision = false,
    bool audio = false,
    LibraryLocator? libraries,
    String? androidNativeLibDir,
    LogSink log = stdoutLogSink,
  }) {
    // Phase 1 (extraction of the flutter_gemma_litertlm FFI core) lands here.
    throw UnimplementedError(
      'litertlm_dart 0.0.x is the API contract only — '
      'the runtime lands in 0.1.0 (see docs/design).',
    );
  }
}

/// A loaded model. Owns native engine state; conversations are created from
/// it and must be closed before the engine.
abstract interface class Engine {
  /// Creates an isolated conversation (its own KV-cache / history).
  ///
  /// Generations across conversations of one engine are serialized
  /// internally (the LiteRT-LM C API is not documented reentrant); `cancel`
  /// intentionally bypasses that serialization to interrupt an in-flight
  /// generation.
  Future<Conversation> createConversation({int? maxOutputTokens});

  /// Live conversations created by this engine and not yet closed.
  int get activeConversations;

  /// Releases the native engine. Closes remaining conversations first.
  Future<void> close();
}
