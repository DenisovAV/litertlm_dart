import 'backend.dart';
import 'conversation.dart';
import 'exceptions.dart';
import 'internal/client.dart';
import 'library_locator.dart';
import 'log_sink.dart';
import 'prompt.dart';

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
  ///
  /// Throws [LibraryLoadException] if the native libraries cannot be located,
  /// [EngineCreateException] (with the native-log tail) if the model fails to
  /// load.
  ///
  /// [captureNativeLog] (default true) redirects native stderr (absl/glog) to
  /// a temp file so [EngineCreateException] can carry it — but on macOS/Linux
  /// that redirect also swallows the process's own stdout. A CLI/server that
  /// prints to the console should pass `false`.
  static Future<Engine> createEngine({
    required String modelPath,
    Backend backend = Backend.cpu,
    Backend? visionBackend,
    int maxTokens = 2048,
    bool vision = false,
    bool audio = false,
    int maxNumImages = 1,
    LibraryLocator? libraries,
    String? androidNativeLibDir,
    LogSink log = stdoutLogSink,
    bool captureNativeLog = true,
  }) async {
    final client = LiteRtLmFfiClient(
      log: log,
      androidNativeLibDir: androidNativeLibDir,
      libraries: libraries,
      captureNativeLogInDebug: captureNativeLog,
    );
    try {
      await client.initialize(
        modelPath: modelPath,
        backend: backend.wireName,
        visionBackend: (visionBackend ?? backend).wireName,
        maxTokens: maxTokens,
        enableVision: vision,
        maxNumImages: vision ? maxNumImages : 0,
        enableAudio: audio,
      );
    } on LiteRtLmException {
      rethrow;
    } catch (e) {
      // The client throws plain Exceptions/StateErrors for load + create
      // failures; map them to the package's typed hierarchy, carrying the
      // native-log tail so an engine-create failure is diagnosable.
      final message = e.toString();
      if (message.contains('library') || message.contains('dlopen')) {
        throw LibraryLoadException(
          message,
          attemptedPaths: [
            client.librariesForDiagnostics.mainLibraryPath,
            client.librariesForDiagnostics.proxyLibraryPath,
          ],
        );
      }
      throw EngineCreateException(
        message,
        nativeLogTail: client.nativeLogTail(),
      );
    }
    return _EngineImpl(client);
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

class _EngineImpl implements Engine {
  _EngineImpl(this._client);
  final LiteRtLmFfiClient _client;
  final Set<_ConversationImpl> _conversations = {};
  bool _closed = false;

  @override
  int get activeConversations => _conversations.length;

  @override
  Future<Conversation> createConversation({int? maxOutputTokens}) async {
    if (_closed) {
      throw DisposedException('Engine is closed.');
    }
    final handle = _client.createConversationHandle(
      maxOutputTokens: maxOutputTokens,
    );
    final convo = _ConversationImpl(handle, _forget);
    _conversations.add(convo);
    return convo;
  }

  void _forget(_ConversationImpl c) => _conversations.remove(c);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final c in _conversations.toList()) {
      await c.close();
    }
    _client.shutdown();
  }
}

class _ConversationImpl implements Conversation {
  _ConversationImpl(this._handle, this._onClose);
  final LiteRtLmConversationHandle _handle;
  final void Function(_ConversationImpl) _onClose;
  bool _closed = false;

  @override
  Stream<String> generateStream(Prompt prompt) {
    if (_closed) {
      throw DisposedException('Conversation is closed.');
    }
    return _handle
        .chat(
          prompt.text,
          imageBytes: prompt.images.isEmpty ? null : prompt.images,
          audioBytes: prompt.audio,
        )
        .handleError((Object e) => throw GenerationException(e.toString()));
  }

  @override
  Future<String> generate(Prompt prompt) async {
    final buf = StringBuffer();
    await for (final chunk in generateStream(prompt)) {
      buf.write(chunk);
    }
    return buf.toString();
  }

  @override
  void cancel() {
    if (_closed) return;
    _handle.cancelGeneration();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _handle.close();
    _onClose(this);
  }
}
