# litertlm_dart — design

Date: 2026-07-07. Status: approved (design); implementation not started.

## 1. Purpose and boundaries

`litertlm_dart` is a **pure Dart** package (no Flutter SDK dependency) that
solely owns everything LiteRT-LM:

* delivery of the native prebuilts (Native Assets `hook/build.dart`),
* loading them (per-platform strategies),
* FFI bindings to the LiteRT-LM C API,
* engine / conversation lifecycle,
* streaming generation, multimodal (vision/audio) input,
* native log capture.

Consumers: `flutter_gemma_litertlm` (thin Flutter adapter), CLI / server
Dart apps, tests. The implementation is an extraction of the battle-tested
FFI layer of `flutter_gemma_litertlm` (verified on Android, iOS, macOS,
Windows, Linux), NOT a rewrite of the native logic.

### Positioning vs `litertlm` (pub.dev, yangyuan)

An existing package `litertlm` (Andrew Yang, Microsoft; active, 0.0.8) is a
lightweight Flutter bridge to the *official* per-platform LiteRT-LM
distributions (Swift package on Apple, Maven+JNI on Android, NPM on web,
CLI distribution on Windows/Linux). It requires Flutter and inherits the
limits of the official packaging (e.g. no Windows ARM64).

`litertlm_dart` is the opposite trade-off: direct C-API FFI on every
platform with our own prebuilts (custom patches: iOS GPU-registry dlopen
fix, QNN / Intel NPU dispatch), one code path everywhere, usable from any
Dart. The `_dart` suffix marks that difference (pub.dev's anti-typosquatting
blocks `litert_lm` as too similar to `litertlm`).

## 2. Public API

```dart
final engine = await LiteRtLm.createEngine(
  modelPath: '/path/gemma-4-E2B-it.litertlm',
  backend: Backend.gpu,              // enum {cpu, gpu, npu} — not strings
  visionBackend: Backend.cpu,        // typed Mali-freeze escape hatch (#324)
  maxTokens: 2048,                   // clamped up to the model's kv_cache_max_len
  vision: true, audio: false,
  libraries: LibraryLocator.defaultForPlatform(),
  androidNativeLibDir: null,         // adapter passes it for NPU; unused in CLI
  log: LogSink.stdout,               // injectable, replaces debugPrint
);

final convo = await engine.createConversation(maxOutputTokens: 100);
final stream = convo.generateStream(
  Prompt.user(text: 'what is on the photo?', images: [bytes]),
);
await for (final chunk in stream) { /* Stream<String> */ }
convo.cancel();          // outside the generation mutex, interrupts in-flight
await convo.close();
await engine.close();
```

Design decisions relative to the current `LiteRtLmFfiClient`:

* **One session API.** The handle-based multi-conversation path is the only
  one; the legacy single-conversation API dies at the package boundary.
* **JSON marshalling is private.** `buildMessageJson` / `extractTextFromResponse`
  become internals behind `Prompt` / typed results.
* **Typed backends** (enum, incl. separate `visionBackend`) instead of
  `backend_str` / `vision_backend_str` strings.
* **Typed exceptions**: `LibraryLoadException`, `EngineCreateException`
  (carries the native-log tail), `GenerationException`.
* **Documented internal behaviors**: generation calls across conversations
  are serialized by a mutex (LiteRT-LM C API is not documented reentrant);
  `cancel` intentionally bypasses it.
* Second entrypoint `package:litertlm_dart/bindings.dart` exports the raw
  ffigen bindings with no stability guarantees.

## 3. Package layout

```
litertlm_dart/
├── hook/build.dart                  # moved from flutter_gemma_litertlm:
│                                    # GitHub-release prebuilts, SHA256 pinned,
│                                    # Apple-only stage(); owns the libLiteRtLm bundle
├── lib/litertlm_dart.dart           # public API
├── lib/bindings.dart                # low-level entrypoint
└── lib/src/
    ├── engine.dart / conversation.dart / prompt.dart / backend.dart / exceptions.dart
    ├── library_locator.dart         # §4
    ├── native_log.dart              # LogSink + StreamProxy stderr capture
    ├── bindings/litert_lm_bindings.dart   # moved as-is
    └── internal/client.dart         # extracted battle-tested core, split, Flutter-free
```

Dependencies: `ffi`, `mutex`, `crypto`, `hooks`, `code_assets` — zero Flutter.

## 4. Native library resolution — injectable strategy

`LibraryLocator` replaces today's hardcoded per-platform if/else:

* `defaultForPlatform()` — reproduces current behavior (Native Assets
  locations, Apple framework names, Linux RTLD_GLOBAL ordering through
  StreamProxy's `stream_proxy_load_global`).
* `fromDirectory(path)` — CLI/server: point at a directory of .so/.dylib/.dll.
* `custom(...)` — full control.

The Android NPU native-lib dir (today a `MethodChannel('flutter_gemma_bundled')
→ getNativeLibraryDir` call) becomes a plain constructor parameter; the
Flutter adapter keeps the channel and passes the string down.

The two Flutter touchpoints of the current client (debugPrint logging and
that MethodChannel) are exactly the two injectable seams (`LogSink`,
`androidNativeLibDir`); nothing else in the FFI layer needs Flutter.

## 5. flutter_gemma_litertlm after migration

Stays a thin adapter: registry provider + `ffi_inference_model.dart`
(implements flutter_gemma's `InferenceModel` over `Conversation`), the web
arm (unchanged), the `flutter_gemma_bundled` MethodChannel, and the chat
template / function-calling parsing (flutter_gemma-level knowledge). Its
`hook/build.dart` moves into `litertlm_dart`; single-registrant coordination
with `flutter_gemma_embeddings` is preserved — only the bundle owner changes
(Flutter builds run hooks of pure Dart packages in the graph natively).
Dependency: path during development, hosted at release.

## 6. Testing

* Unit (`dart test`, fast, no native): Prompt/Backend/exception contracts,
  LibraryLocator resolution, response parsing.
* macOS host smoke: a small CLI example in `example/` doing a real
  generation via `dart run` (native assets for pure Dart are experimental;
  fallback — `fromDirectory` pointed at the flutter_gemma native cache).
* Cross-platform gate unchanged: the 23-test `litertlm_ffi_test.dart` suite
  of the flutter_gemma example app after the adapter migration, on all five
  native platforms.

## 7. Phases

1. **litertlm_dart standalone**: package + move bindings/core + typed API +
   hook; CLI smoke green on macOS.
2. **Adapter migration**: flutter_gemma_litertlm rewires to litertlm_dart;
   monorepo tests + the 5-platform gate green.
3. **Later (out of scope)**: managed isolate worker; optional tool-calling
   loop and Benchmark API (ideas worth borrowing from yangyuan's package);
   CompiledModel alignment per Google's recommendations.

## 8. Publication gate

pub.dev publication (starting with 0.0.1) happens ONLY after: full code
review of the extraction + integration tests green on all five native
platforms. No name-holding release before that.
