# litertlm_dart — Phase 1 implementation plan (autonomous)

Date: 2026-07-07. Scope: **runtime only** (per design doc §7 phase 1). Extract
the battle-tested FFI runtime from `flutter_gemma_litertlm` into `litertlm_dart`
behind the already-approved typed API, with ZERO Flutter dependency. Chat
templating / function-calling / history-JSON stay in the flutter_gemma adapter
(they are flutter_gemma knowledge, not runtime).

This plan is self-contained: an engineer (or a fresh session) can execute it
top-to-bottom without re-deriving decisions. Every step ends in a verifiable
state. The gate is unchanged (design §8): pub.dev stable release only after
full review + integration tests green on all 5 native platforms.

---

## 0. Current state (starting point)

- pub.dev name **reserved**: `litertlm_dart 0.0.1-dev.1` under publisher
  `sashadenisov.dev` (published 2026-07-06). Name is ours.
- GitHub `DenisovAV/litertlm_dart` (public), 2 commits: skeleton+design, and
  the typed API contract + unit tests + cross-platform integration host (TDD
  red — everything past the contract test throws `UnimplementedError`).
- Public API already written and unit-tested (12 tests green):
  `LiteRtLm.createEngine` / `Engine` / `Conversation` / `Prompt` / `Backend` /
  sealed `LiteRtLmException` / `LibraryLocator` / `LogSink`. Pure logic
  (locator, prompt, exceptions) is real; native path is `UnimplementedError`.
- Integration host `example/flutter_host/` (ios/android/macos/windows/linux)
  with 9 e2e tests, currently red by design.

## Extraction source (flutter_gemma_litertlm)

`packages/flutter_gemma_litertlm/`:
- `lib/src/ffi/litert_lm_bindings.dart` (~2035 lines, ffigen output from
  `native/litert_lm/include/engine.h`, 8 external funcs) — moves ~as-is.
- `lib/src/ffi/litert_lm_client.dart` (~1529 lines) — the runtime core:
  library loading (`_ensureBindings`, per-platform dlopen + StreamProxy
  RTLD_GLOBAL + stderr redirect), `initialize` (engine_create + clamp),
  conversation create/close, `startVirtualTurn`/`sendMessageStreamRaw`
  streaming, cancel, `dumpNativeLog`, the `_nativeMutex` serialization, and
  the JSON helpers `buildMessageJson`/`buildHistoryJson`/
  `extractTextFromResponse`.
- `lib/src/ffi/ffi_inference_model.dart` (~712 lines) — the flutter_gemma
  `InferenceModel`/`InferenceModelSession` implementation over the client.
  This is the ADAPTER surface; it does NOT move — it gets rewritten in phase 2
  to sit on `litertlm_dart`'s `Conversation`.
- `hook/build.dart` (~789 lines) — Native Assets hook: fetches prebuilts from
  GitHub release, SHA256-verified, Apple-only `stage()`. Owns the libLiteRtLm
  bundle. **Moves** to litertlm_dart.
- `native/litert_lm/` — build scripts, `stream_proxy.c`, `include/engine.h`,
  `prebuilt/` (259 MB, git-ignored working copies). The bundle source of truth
  is the GitHub release `native-v0.13.1-a`; the hook downloads from there.

## Coupling to sever (flutter_gemma imports in the FFI layer)

From `grep` of `lib/src/ffi/*.dart` (excluding stubs):
- `flutter_gemma/flutter_gemma_interface.dart`, `core/domain/platform_types.dart`
  — types (`InferenceModel`, `PreferredBackend`). Runtime side needs only
  `PreferredBackend`-equivalent → replaced by our `Backend` enum. The
  `InferenceModel` interface stays in the adapter.
- `core/utils/gemma_log.dart` → replaced by our `LogSink`.
- `flutter/foundation.dart` (debugPrint) → `LogSink`.
- `flutter/services.dart` (`MethodChannel('flutter_gemma_bundled')` →
  `getNativeLibraryDir` for Android NPU) → constructor param
  `androidNativeLibDir`, the adapter keeps the channel and passes the string.
- `core/{tool,model,message,chat,extensions,parsing/*}` — chat/function-calling
  knowledge → STAY in the adapter, never move.

---

## Phase 1 steps

Each step is a commit. Run `dart analyze` + `dart test` after every step
(both must stay green — the pure-Dart parts always compile). The native path
becomes runnable only at step 6; steps 1–5 are Flutter-free refactors of moved
code that compile against the bindings but aren't exercised until the smoke.

### Step 1 — move bindings + native sources, add ffigen config

- Copy `litert_lm_bindings.dart` → `lib/src/bindings/litert_lm_bindings.dart`;
  it has no flutter_gemma imports, moves verbatim.
- Copy `native/litert_lm/{include/engine.h, stream_proxy.c, build_*.sh,
  patch_c_api.sh, verify_tarball_manifest.sh}` → `native/litert_lm/`.
- Add `ffigen.yaml` reproducing the generation (source `engine.h`, output
  `lib/src/bindings/litert_lm_bindings.dart`) so bindings can be regenerated,
  not hand-maintained.
- Export raw bindings via `lib/bindings.dart` (already stubbed in the design).
- **Verify:** `dart analyze` clean; bindings compile in isolation.

### Step 2 — the Flutter-free runtime core (`internal/client.dart`)

Port `litert_lm_client.dart` into `lib/src/internal/client.dart`, mechanically
replacing the four coupling points:
- `gemmaLog(...)` / `debugPrint(...)` → the injected `LogSink log`.
- `PreferredBackend` → our `Backend`; the `backend_str`/`vision_backend_str`
  mapping (incl. the #324 Mali `vision=cpu, text=gpu` split) becomes a private
  `_backendString(Backend)` — same strings, typed input.
- The per-platform dlopen block → driven by the injected `LibraryLocator`
  (main + proxy paths come from the locator; the RTLD_GLOBAL ordering and the
  StreamProxy `stream_proxy_load_global`/`stream_proxy_redirect_stderr` calls
  stay identical).
- `MethodChannel(...).getNativeLibraryDir` → the `androidNativeLibDir` param.
- Keep verbatim: `_nativeMutex` serialization, the KV-cache clamp
  (`clampLitertlmContextTokens` — 1024 floor), `dumpNativeLog` (still reads +
  truncates the redirected stderr file, but pipes through `LogSink`), the
  virtual-conversation streaming machinery, cancel-outside-mutex.
- Keep the JSON helpers PRIVATE here (`_buildMessageJson`,
  `_extractTextFromResponse`) — they marshal `Prompt`→C and C→text; the public
  API never exposes JSON.
- **Verify:** `dart analyze` clean; no `package:flutter*` or `package:flutter_gemma`
  import remains in `lib/` (grep asserts this).

### Step 3 — wire the typed public API to the core

Replace the `UnimplementedError` bodies:
- `LiteRtLm.createEngine(...)` → build a `LibraryLocator` (default if null),
  construct the client, call its `initialize(...)`, return an `_EngineImpl`.
- `_EngineImpl.createConversation` → client conversation handle →
  `_ConversationImpl`; track count for `activeConversations`; `DisposedException`
  after close.
- `_ConversationImpl.generateStream(Prompt)` → `_buildMessageJson(prompt)` →
  client streaming → `Stream<String>`; `generate` = joined; `cancel` →
  client cancel; `close` → client close.
- Map native failures to typed exceptions: load failure →
  `LibraryLoadException(attemptedPaths: locator paths)`; engine_create failure
  → `EngineCreateException(nativeLogTail: last N lines of dumpNativeLog)`;
  stream error → `GenerationException`.
- **Verify:** unit tests still green (they don't touch native); the contract
  test that asserted `throwsUnimplementedError` is updated/removed.

### Step 4 — move the Native Assets hook

- Copy `hook/build.dart` from flutter_gemma_litertlm, adjust the package name
  and bundle id (`flutter_gemma_litertlm` → `litertlm_dart`), keep the GitHub
  release pin (`native-v0.13.1-a`), SHA256 map, and Apple-only `stage()`.
- Preserve the single-registrant coordination marker used with
  `flutter_gemma_embeddings` (both share libLiteRtLm). **Critical:** the
  marker/owner name changes owner from flutter_gemma_litertlm to litertlm_dart
  — document that phase 2 must update embeddings' expectation, or keep the
  same marker string so nothing breaks mid-migration.
- Add `hooks` + `code_assets` deps to pubspec.
- **Verify:** `dart --enable-experiment=native-assets run` in `example/cli/`
  (step 5) resolves the bundle; on macOS host the dylibs land in the build dir.

### Step 5 — CLI smoke example (`example/cli/`)

- Minimal `bin/generate.dart`: `LiteRtLm.createEngine(modelPath: args[0],
  backend: Backend.cpu)` → one conversation → stream a reply to stdout.
- If native-assets-for-pure-Dart is too experimental to resolve the bundle,
  fall back to `LibraryLocator.fromDirectory(<flutter_gemma native cache>)`
  and load prebuilts from `~/Library/Caches/flutter_gemma/native/macos_arm64/`.
- **Verify (macOS host, THE phase-1 milestone):** `dart run
  example/cli/bin/generate.dart /abs/gemma-4-E2B-it.litertlm` prints a real
  streamed reply. This proves the runtime works with zero Flutter.

### Step 6 — green the cross-platform integration host

- The 9 e2e tests in `example/flutter_host/integration_test/` already target
  the public API; with the runtime implemented they should pass.
- Stage a `.litertlm` model per platform (macOS/Linux/Windows: any readable
  path; iOS: `devicectl copy to … Documents/`; Android: `adb push`).
- Run on each: `flutter test integration_test/litertlm_dart_test.dart -d
  <device> --dart-define=MODEL_PATH=/abs/model.litertlm` (NEVER `flutter
  drive` on native — flutter_gemma rule).
- **Verify (THE publication gate, design §8):** green on Android, iOS, macOS,
  Windows, Linux.

---

## Phase 2 (separate plan, after phase 1 is green) — adapter migration

Rewrite `flutter_gemma_litertlm` to depend on `litertlm_dart`:
- `ffi_inference_model.dart` reimplemented over `Conversation` (keeps the
  `InferenceModel`/`InferenceModelSession` contract flutter_gemma expects).
- The `flutter_gemma_bundled` MethodChannel + Android NPU dir wiring stays in
  the adapter, passed to `createEngine(androidNativeLibDir:)`.
- Chat template / function-calling parsing (core/tool, core/parsing) stays.
- Move the hook OUT of flutter_gemma_litertlm (litertlm_dart owns it now);
  reconcile the single-registrant marker with flutter_gemma_embeddings.
- Gate: monorepo tests + the 23-test `litertlm_ffi_test.dart` suite green on
  all 5 native platforms.

## Risks / watch-items

1. **native-assets for pure Dart is experimental** — step 5 has the
   `fromDirectory` fallback so the smoke never blocks on it.
2. **Single-registrant marker** shared with embeddings — the ONE cross-package
   invariant; changing bundle owner mid-migration can strand a stale owner.
   Keep the marker string stable across the ownership move.
3. **iOS/macOS companion-dylib framework staging** is done by the host Xcode
   project's Run Script phase, NOT the hook — the integration host needs that
   phase (copy from flutter_gemma example's pbxproj) or GPU load fails.
4. **Windows never `stage()`** (splits companion DLLs, hangs cancel/close) —
   Apple-only, already in the hook; don't regress.
5. Keep bindings ffigen-regenerable, not hand-edited, or they drift from
   `engine.h`.
