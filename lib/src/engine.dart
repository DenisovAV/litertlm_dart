import 'dart:async';

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
  /// Throws [LibraryLoadException] if the native libraries cannot be located
  /// or loaded, [EngineCreateException] (with the native-log tail when
  /// available) if the model fails to load.
  ///
  /// [captureNativeLog] (default FALSE) redirects native stderr (absl/glog) to
  /// a temp file so [EngineCreateException] can carry the tail — but on
  /// macOS/Linux that redirect also swallows the process's own stdout, so it
  /// defaults off for the CLI/server audience. A Flutter app (whose stdout
  /// isn't a console) can pass `true` to get richer engine-failure diagnostics.
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
    bool captureNativeLog = false,
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
      // The client now throws the typed hierarchy at the source
      // (LibraryLoadException at dlopen/preload sites, EngineCreateException
      // at engine/settings-create sites), already carrying attemptedPaths /
      // nativeLogTail. No fragile message string-matching here.
      rethrow;
    } catch (e) {
      // Last-resort catch for anything the client didn't type — surface it as
      // an engine-create failure with whatever native tail exists.
      throw EngineCreateException(
        e.toString(),
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
  ///
  /// Implement this interface only for testing/fakes; new methods may be
  /// added in minor versions.
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
    final LiteRtLmConversationHandle handle;
    try {
      handle = _client.createConversationHandle(
        maxOutputTokens: maxOutputTokens,
      );
    } on LiteRtLmException {
      rethrow;
    } catch (e) {
      throw EngineCreateException('Failed to create conversation: $e');
    }
    final convo = _ConversationImpl(handle, _forget);
    _conversations.add(convo);
    return convo;
  }

  void _forget(_ConversationImpl c) => _conversations.remove(c);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Always tear the native engine down, even if a conversation-close throws
    // — otherwise a single failing conversation delete would leak the engine
    // (shutdown() is the only litert_lm_engine_delete path).
    try {
      for (final c in _conversations.toList()) {
        try {
          await c.close();
        } catch (_) {
          // Per-conversation close failures must not abort engine teardown;
          // shutdown() below force-closes any handles still open.
        }
      }
    } finally {
      _client.shutdown();
    }
  }
}

class _ConversationImpl implements Conversation {
  _ConversationImpl(this._handle, this._onClose);
  final LiteRtLmConversationHandle _handle;
  final void Function(_ConversationImpl) _onClose;
  bool _closed = false;

  /// The controller of the currently-active generation, or null when idle.
  /// Used both to reject overlapping generations and to drain an in-flight
  /// generation before deleting the native conversation on [close].
  StreamController<String>? _active;
  StreamSubscription<String>? _activeSub;

  @override
  Stream<String> generateStream(Prompt prompt) {
    if (_closed) {
      throw DisposedException('Conversation is closed.');
    }
    if (_active != null) {
      // The native conversation mutates one shared history; two overlapping
      // generations would interleave nondeterministically. One in flight at
      // a time per conversation.
      throw StateError(
        'A generation is already in flight on this conversation.',
      );
    }
    // A StreamController wrapper (not async*) so close() has a reliable
    // completion signal to await, and cancelling the returned stream reliably
    // stops the native generation and frees the mutex — the async* finally
    // only runs when the consumer drains/cancels, which is the exact deadlock
    // the client's virtual path was rewritten to avoid.
    final controller = StreamController<String>();
    _active = controller;
    controller.onListen = () {
      _activeSub = _handle
          .chat(
            prompt.text,
            imageBytes: prompt.images.isEmpty ? null : prompt.images,
            audioBytes: prompt.audio,
          )
          .listen(
            controller.add,
            onError: (Object e, StackTrace st) {
              controller.addError(GenerationException(e.toString()), st);
            },
            onDone: () {
              _active = null;
              _activeSub = null;
              controller.close();
            },
          );
    };
    controller.onCancel = () async {
      await _activeSub?.cancel();
      _active = null;
      _activeSub = null;
    };
    return controller.stream;
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
    // If a generation is in flight, cancel it and wait for the native stream
    // to finish BEFORE deleting the conversation — deleting the native
    // conversation pointer out from under a running stream is a use-after-free.
    final active = _active;
    if (active != null) {
      if (_activeSub != null) {
        _handle
            .cancelGeneration(); // native stop -> stream emits CANCELLED/done
        await active.done.catchError((_) {});
      } else {
        // Never listened: no native generation started — just tear down.
        await active.close();
      }
      _active = null;
      _activeSub = null;
    }
    _handle.close();
    _onClose(this);
  }
}
