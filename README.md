# litertlm_dart

Pure Dart runtime for [Google's LiteRT-LM](https://github.com/google-ai-edge/litert-lm):
FFI bindings, engine/conversation lifecycle, and streaming on-device LLM
inference — with **no Flutter dependency**. Runs from a CLI, a server, or a
Flutter app (via an adapter such as `flutter_gemma_litertlm`).

Native prebuilts for all five targets — **Android, iOS, macOS, Windows, Linux** —
are fetched and bundled by a [Native Assets](https://dart.dev/interop/c-interop#native-assets)
build hook (SHA256-verified), so there is no manual native setup.

## Usage

```dart
import 'dart:io';
import 'package:litertlm_dart/litertlm_dart.dart';

Future<void> main() async {
  final engine = await LiteRtLm.createEngine(
    modelPath: 'gemma-4-E2B-it.litertlm',
    backend: Backend.gpu, // falls back to CPU when unavailable
    maxTokens: 2048,      // context window (input + output), not reply length
  );

  final convo = await engine.createConversation(maxOutputTokens: 256);
  await for (final chunk in convo.generateStream(const Prompt.user(text: 'Hi!'))) {
    stdout.write(chunk);
  }

  await convo.close();
  await engine.close();
}
```

Conversations keep their own history, run serialized within an engine, and can
be cancelled mid-generation (`convo.cancel()`). `generate()` returns the full
reply; `generateStream()` yields chunks as they are produced.

## Features

* Typed `Engine` → `Conversation` → `Stream<String>` API over the LiteRT-LM C API.
* CPU / GPU / NPU backend selection, with an optional separate vision backend.
* Multimodal prompts (image / audio) for models that support them.
* `maxOutputTokens` reply cap and cancellable streaming.
* A typed exception hierarchy (`LibraryLoadException`, `EngineCreateException`,
  `GenerationException`, `DisposedException`) that carries native-log tails and
  attempted library paths for diagnosis.
* Pluggable native-library resolution: the Native Assets hook for app builds,
  or directory-based loading (`LibraryLocator`) for CLI and server Dart.
* Low-level raw C-API bindings exported via `package:litertlm_dart/bindings.dart`.

## Running the CLI example

Native Assets are still behind an experiment flag for standalone `dart run`:

```sh
cd example/cli
dart --enable-experiment=native-assets run bin/generate.dart --model /path/to/model.litertlm
```

A cross-platform integration host (`example/flutter_host`) exercises the full
API end to end on all five platforms.

## Model files

`litertlm_dart` runs `.litertlm` models (e.g. Gemma 4 E2B, Qwen3, FunctionGemma
from the [`litert-community`](https://huggingface.co/litert-community) org). It
does not download models — pass a readable path to `createEngine`.

## Scope

This package is **runtime only**. Chat templating, function calling, and other
model-conversation concerns live one layer up in the Flutter adapter
([`flutter_gemma`](https://pub.dev/packages/flutter_gemma) /
`flutter_gemma_litertlm`), which consumes `litertlm_dart`'s `Conversation` API —
`litertlm_dart` owns everything LiteRT-LM, the Flutter side stays a thin adapter.
