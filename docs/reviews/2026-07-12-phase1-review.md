# litertlm_dart — Phase 1 pre-0.1.0 review

Date: 2026-07-12. Scope: full phase-1 diff (c837894..HEAD). Reviewers: 5
parallel agents (FFI memory-safety, API/lifecycle, LibraryLocator+hook,
silent-failure, type-design). Copilot second-opinion attempted but hit its
monthly quota. The 5-platform gate (macOS/Android/Windows/Linux/iOS, 9/9 each
with real Gemma-4 E2B) passed — these findings are hardening + API-durability
for a 0.1.0 that becomes a long-term public contract, NOT gate regressions.

Findings confirmed by ≥2 independent reviewers are marked ★.

## CRITICAL (correctness — fix before publish)

1. ★ **`close()` during in-flight generation → native use-after-free of the
   conversation pointer.** `_ConversationImpl.close()` (engine.dart:173) →
   `_handle.close()` → `litert_lm_conversation_delete(conv)` runs synchronously
   with no cancel and no wait, while a native stream may still be running on
   `conv`. `Engine.close()` (engine.dart:131) force-closes every conversation,
   so a timeout→close pattern or shutdown-mid-generate frees `conv` under the
   streaming thread → crash; the abandoned `await for` may also hang forever.
   The virtual-session path guards exactly this (`_virtualTurnInFlight` /
   `_pendingReleaseToken` defer teardown); the direct handle path has no
   equivalent. Flagged independently by the FFI-memory and API-lifecycle
   reviewers. Fix: `close()` must `cancel()` + await/drain the active stream
   before deleting (mirror the virtual path's deferral).

## IMPORTANT

2. ★ **Error classification by substring (`message.contains('library') ||
   'dlopen'`) misroutes real library-load failures** (engine.dart:66). Every
   hand-authored load throw in client.dart (Android API<30, Linux/Windows
   RTLD_GLOBAL preload, ABI/platform UnsupportedError) contains NEITHER
   substring → all become `EngineCreateException`, losing `attemptedPaths`; on
   Windows/Android the stderr redirect isn't wired so the tail is null too. The
   documented contract ("throws LibraryLoadException if libs can't be located")
   is then never honored for an actual missing lib on those OSes. Reverse also
   fires: a modelPath containing "library" mistypes an engine-create failure as
   LibraryLoadException. Flagged by 3 reviewers. Fix: throw the typed exceptions
   at the SOURCE in client.dart; reduce createEngine to `on LiteRtLmException
   rethrow`.

3. ★ **Hook non-owner registration skip is SILENT** (hook/build.dart:645).
   Same-version/different-owner (the COMMON case for the shared bundle) →
   `iAmRegistrant=false` → returns having registered ZERO CodeAssets, exit 0,
   no stderr. This is the stale-owner outage we hit on all 5 platforms this
   session. Flagged by 2 reviewers. Fix (1 line, non-behavioral): `stderr.writeln`
   at the skip naming the recorded owner + the `flutter clean` + cache-wipe
   remedy. (Full coordination redesign is phase-2.)

4. **`Engine.close()` aborts on the first throwing conversation-close → native
   engine leak** (engine.dart:128). The `for … await c.close()` loop has no
   try/finally, so a throw skips `_client.shutdown()` (the only
   `litert_lm_engine_delete` path). Fix: shutdown in finally.

5. **`settings` leaked on every failing engine-create** (client.dart:649→815).
   The `finally` frees the 4 string pointers but not `settings`; any throw
   between create and success (bad model, OOM, wrong ABI, NPU-dir StateError)
   leaks it. Common failure. Fix: free `settings` in the finally.

6. **`_sendMessageStreamRawOn` uses `async*` → mutex-held-forever deadlock**
   (client.dart:1156). An abandoned-without-cancel direct-handle stream never
   runs the generator's finally, holding `_nativeMutex` forever and deadlocking
   every other session. The virtual path was rewritten to a StreamController to
   avoid exactly this; the direct path still has it. Fix: StreamController.

7. **`fromDirectory` (CLI/server) only wired on macOS; Linux/Windows ignore the
   locator during RTLD_GLOBAL preload** (client.dart:441/494). Linux hardcodes
   `<exe>/lib`, Windows preloads bare DLL names — a `dart run` from a directory
   of bare libs throws before the final open. Latent: the gate used Native
   Assets (defaultForPlatform), not fromDirectory, on Linux/Windows. Fix: derive
   the preload dir from `_libraries.mainLibraryPath` parent (as macOS does).

8. **Exception `toString()` drops the diagnostic payload** (exceptions.dart:11).
   The inherited base toString shows only `message`; `catch (e) { log('$e'); }`
   loses `attemptedPaths` / `nativeLogTail` — the exact data the hierarchy
   exists to carry. Fix: override toString in the two subtypes.

9. **Streaming error branch closes the NativeCallable unconditionally**
   (client.dart:1389) — dangling trampoline UAF + proxy leak IF native ever
   emits a callback after a non-final error/CANCELLED. Correctness hinges on
   native always setting `is_final` on the terminal error callback. Verify
   against the LiteRT-LM C API; guard if not guaranteed.

## Type-design freeze-risks (cheap now, breaking after 0.1.0 ships)

10. **`LibraryLocator` bakes "exactly 2 libraries (main+proxy)" into the public
    contract** (public `mainLibraryPath`/`proxyLibraryPath` + `.custom`). If the
    native build folds/splits libraries, every field + factory breaks. The
    fields are only read internally. Make the set opaque or
    `.custom(List<String> librariesInLoadOrder)`.

11. **`captureNativeLog: true` default swallows process stdout on macOS/Linux** —
    hostile to the CLI/server audience the pubspec sells first. Changing a
    default is a behavioral break. Decide now: default `false` (Flutter adapter
    opts in), or fix capture so it doesn't steal stdout.

12. **`GenerationException` has no `nativeLogTail`** — yet the #318
    `DYNAMIC_UPDATE_SLICE`/executor.cc crash happens at GENERATION time. Adding
    the field is additive; do it now.

13. **`Prompt` flat `text`/`images`/`audio` can't express interleaved multimodal
    content** (image-token position is semantically meaningful for Gemma
    vision). Sketch a `List<ContentPart>` model and define `Prompt.user` as sugar
    over it from day one; at minimum default `text = ''` (image-only prompts).

14. **Mark sealed exception leaves `final class`; mark `Backend.wireName`
    `@internal`** — close the type tree and hide the wire-string mapping.

## MINOR

- `nativeLogTail`/`_dumpNativeLog` read the whole (multi-MB) redirect log into
  memory for a 40-line tail; `nativeLogTail` swallows all errors via `catch (_)`.
- Isolate companion-preload ignores `loadGlobal`'s null return (main thread
  logs it) — a preload failure aborts the process with no breadcrumb.
- Integration-test model resolution accepts a truncated/stale staged file
  (`existsSync && length>0`) — test-only; add a size floor.
- `targetLiteRtLmVersion` ('0.13.1') and the hook version ('0.13.1-a') are
  independent constants with no cross-check.
- Concurrent `generateStream` on one conversation is unguarded (serialize ≠
  reject) — add a `_generating` flag or document single-in-flight.
- `createConversation` has no error mapping (raw client exceptions escape).
- Checksum-mismatch / non-owner download-defer produce zero-lib builds that
  surface only at runtime (matches upstream flutter_gemma; awareness only).

## Verified correct (closed out)
Double-close idempotence; `cancel()` idle/closed/in-flight safety;
`Backend.wireName` mapping; `visionBackend ?? backend` (#324); `maxTokens: 2048`
(#318); macOS companion-preload frees its pointers; isolate boundary sends only
sendable values; `_createRawConversation`/`_getMetricsOn`/`outProxyFn` free on
all paths; atomic hook extract + commit-point marker (no stale marker on torn
download); Apple-only `stage()` gating; empty-chunk drop is intentional (isFinal
handled separately); stderr-redirect failure is logged, not silent.

## Recommendation: REQUEST CHANGES before 0.1.0

The runtime is proven (5-platform gate, real E2B). But 0.1.0 is a permanent
public contract, so:
- **Fix before publish (correctness):** #1 (UAF), #4 (engine leak), #5 (settings
  leak), #6 (mutex deadlock), #3 (1-line silent-skip warning), #2/#8 (typed
  errors at source + toString). #9 needs a native-behavior check.
- **Decide before freeze (API):** #11 (captureNativeLog default), #10
  (LibraryLocator opacity), #12 (GenerationException.nativeLogTail), #13 (Prompt
  parts sketch), #14 (final leaves). Cheap now, breaking later.
- **Latent:** #7 (fromDirectory Linux/Windows) — before advertising CLI on
  those OSes.
