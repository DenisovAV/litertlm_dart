# litertlm_dart

Pure Dart runtime for [Google's LiteRT-LM](https://github.com/google-ai-edge/litert-lm):
FFI bindings, engine/conversation lifecycle, and streaming on-device LLM
inference — with **no Flutter dependency**.

> **Status: under active development.** This 0.0.x release holds the package
> name while the battle-tested implementation is extracted from
> [`flutter_gemma_litertlm`](https://pub.dev/packages/flutter_gemma_litertlm).

## What 0.1.0 will provide

```dart
final engine = await LiteRtLm.createEngine(
  modelPath: 'gemma-4-E2B-it.litertlm',
  backend: Backend.gpu,
  maxTokens: 2048,
);
final convo = await engine.createConversation(maxOutputTokens: 256);
await for (final chunk in convo.generateStream(Prompt.user(text: 'Hi!'))) {
  stdout.write(chunk);
}
```

* Typed `Engine` → `Conversation` → `Stream<String>` API over the LiteRT-LM
  C API (Android, iOS, macOS, Windows, Linux).
* CPU / GPU / NPU backend selection, including a separate vision backend.
* Multimodal prompts (vision / audio) for models that support them.
* Pluggable native-library resolution: Native Assets hook for app builds,
  directory-based loading for CLI and server Dart.
* Low-level raw bindings exported via `package:litert_lm/bindings.dart`.

## Relationship to flutter_gemma

[`flutter_gemma`](https://pub.dev/packages/flutter_gemma) and its
`flutter_gemma_litertlm` engine package will consume this package —
`litert_lm` owns everything LiteRT-LM, the Flutter side stays a thin adapter.
