# Testing litertlm_dart

Two layers, matching the design doc (§6):

## 1. Unit / contract tests (no native code)

```
dart test
```

Pure Dart, run anywhere, always green. Cover the API contract:
`LibraryLocator` resolution, `Prompt`, typed exceptions.

## 2. Cross-platform integration suite (the publication gate)

Lives in `example/flutter_host/integration_test/litertlm_dart_test.dart` —
a minimal Flutter host app, because pure Dart cannot be executed standalone
on iOS/Android and the host gives one uniform harness on all five targets.

Nine end-to-end tests: engine create/close (CPU + GPU), streamed generation,
history across turns, `maxOutputTokens` cap, cancel of an in-flight
generation, conversation isolation, use-after-close, missing-model error.

Stage a `.litertlm` model on the target (the suite does NOT download), then:

```
cd example/flutter_host
flutter test integration_test/litertlm_dart_test.dart -d DEVICE_ID \
  --dart-define=MODEL_PATH=/absolute/path/model.litertlm
```

Per-platform staging notes:

* **macOS / Linux / Windows** — any path readable by the test process.
* **iOS device** — push into the app container's `Documents/` with
  `xcrun devicectl device copy to … --domain-type appDataContainer` after a
  first install; pass that container path as `MODEL_PATH`.
* **Android** — `adb push` to app-accessible storage.

Native targets always use `flutter test integration_test/... -d <device>`;
`flutter drive` is reserved for web only (upstream Flutter limitation).

> **TDD status:** until the 0.1.0 extraction of the FFI core lands, every
> test past the staging check fails with `UnimplementedError` by design.
> The suite must be green on **all five** native platforms before any
> pub.dev release (design doc §8).
