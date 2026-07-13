# litertlm_dart examples

Minimal end-to-end use of the `litertlm_dart` runtime — create an engine over a
`.litertlm` model, open a conversation, and stream a reply.

```dart
import 'dart:io';
import 'package:litertlm_dart/litertlm_dart.dart';

Future<void> main(List<String> args) async {
  final modelPath = args.isNotEmpty ? args.first : 'gemma-4-E2B-it.litertlm';

  final engine = await LiteRtLm.createEngine(
    modelPath: modelPath,
    backend: Backend.gpu, // falls back to CPU when unavailable
    maxTokens: 2048,      // context window (input + output), not reply length
  );

  final convo = await engine.createConversation(maxOutputTokens: 256);
  await for (final chunk in convo.generateStream(const Prompt.user(text: 'Hi!'))) {
    stdout.write(chunk);
  }
  stdout.writeln();

  await convo.close();
  await engine.close();
}
```

## Runnable projects

* **`cli/`** — a standalone Dart CLI. Native Assets are still behind an
  experiment flag for `dart run`:

  ```sh
  cd cli
  dart --enable-experiment=native-assets run bin/generate.dart --model /path/to/model.litertlm
  ```

* **`flutter_host/`** — a Flutter app that hosts the cross-platform integration
  test suite (`integration_test/litertlm_dart_test.dart`), exercising the full
  API on Android, iOS, macOS, Windows, and Linux.

`.litertlm` models (Gemma 4 E2B, Qwen3, FunctionGemma, …) come from the
[`litert-community`](https://huggingface.co/litert-community) org on HuggingFace.
`litertlm_dart` does not download models — pass a readable path to `createEngine`.
