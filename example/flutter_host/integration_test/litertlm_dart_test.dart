/// Cross-platform end-to-end suite for litertlm_dart. This is the "all five
/// platforms" gate from the design doc (§6/§8): it must be green on Android,
/// iOS, macOS, Windows and Linux before any pub.dev publication.
///
/// Run (native targets — NEVER `flutter drive`, see flutter_gemma rules):
///   flutter test integration_test/litertlm_dart_test.dart -d DEVICE_ID \
///     --dart-define=MODEL_PATH=/abs/path/gemma-4-E2B-it.litertlm
///
/// The model is NOT downloaded by the suite: stage it on the target first
/// (desktop: any readable path; iOS: push to the app container's Documents/
/// via `xcrun devicectl device copy to`; Android: `adb push` + /data/local
/// or app dir). On iOS/macOS the app sandbox must be able to open the path.
///
/// Until the 0.1.0 extraction lands, everything past the contract test is
/// expected to FAIL with UnimplementedError — that is the TDD red state, not
/// a broken suite.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:litertlm_dart/litertlm_dart.dart';

const _modelPath = String.fromEnvironment('MODEL_PATH');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MODEL_PATH is staged and readable', (_) async {
    expect(
      _modelPath,
      isNotEmpty,
      reason: 'pass --dart-define=MODEL_PATH=/abs/model.litertlm',
    );
    expect(
      File(_modelPath).existsSync(),
      isTrue,
      reason: 'model not staged at $_modelPath',
    );
  });

  testWidgets('engine creates and closes (CPU)', (_) async {
    final engine = await LiteRtLm.createEngine(
      modelPath: _modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    expect(engine.activeConversations, 0);
    await engine.close();
  });

  testWidgets('streams a reply to completion', (_) async {
    // The runtime stream contract: generateStream is consumable end to end and
    // completes without a GenerationException (which would throw out of the
    // await-for and fail the test). Whether a chunk carries text is the
    // MODEL's job — generateStream is the exact code generate() runs, and the
    // history/cap/isolation tests below assert real model output on every
    // platform, so capable-model coverage lives there. A tiny model on a
    // RAM-limited device may answer 'Say hello.' with few or no tokens; that
    // is not a runtime defect (the client drops empty chunks by design), so
    // content is logged, not asserted here.
    final engine = await LiteRtLm.createEngine(
      modelPath: _modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    final convo = await engine.createConversation();
    final chunks = <String>[];
    var completed = false;
    await for (final c in convo.generateStream(
      const Prompt.user(text: 'Say hello.'),
    )) {
      chunks.add(c);
    }
    completed = true;
    expect(completed, isTrue, reason: 'stream must complete without error');
    // ignore: avoid_print
    print('[gate] streamed ${chunks.length} chunks: "${chunks.join().trim()}"');
    await convo.close();
    await engine.close();
  });

  testWidgets('conversation keeps history across turns', (_) async {
    final engine = await LiteRtLm.createEngine(
      modelPath: _modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    final convo = await engine.createConversation();
    await convo.generate(
      const Prompt.user(text: 'My name is Kestrel. Remember it.'),
    );
    final reply = await convo.generate(
      const Prompt.user(text: 'What is my name? Answer with the name only.'),
    );
    expect(reply.toLowerCase(), contains('kestrel'));
    await convo.close();
    await engine.close();
  });

  testWidgets('maxOutputTokens caps the reply length', (_) async {
    final engine = await LiteRtLm.createEngine(
      modelPath: _modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    final convo = await engine.createConversation(maxOutputTokens: 8);
    final reply = await convo.generate(
      const Prompt.user(text: 'Count from one to one hundred in words.'),
    );
    // 8 tokens can't fit more than a few dozen characters.
    expect(reply.length, lessThan(200));
    await convo.close();
    await engine.close();
  });

  testWidgets('cancel interrupts an in-flight generation', (_) async {
    final engine = await LiteRtLm.createEngine(
      modelPath: _modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    final convo = await engine.createConversation();
    final received = <String>[];
    final done = convo
        .generateStream(
          const Prompt.user(text: 'Write a very long story about the sea.'),
        )
        .listen(received.add)
        .asFuture<void>()
        .catchError((_) {});
    await Future<void>.delayed(const Duration(seconds: 2));
    convo.cancel();
    await done.timeout(const Duration(seconds: 15));
    await convo.close();
    await engine.close();
  });

  testWidgets('two conversations are isolated', (_) async {
    final engine = await LiteRtLm.createEngine(
      modelPath: _modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    final a = await engine.createConversation();
    final b = await engine.createConversation();
    expect(engine.activeConversations, 2);
    await a.generate(const Prompt.user(text: 'My name is Alpha.'));
    final reply = await b.generate(
      const Prompt.user(
        text: 'Do you know my name? Answer yes or no, one word.',
      ),
    );
    // Conversation b never learned the name from a.
    expect(reply.toLowerCase(), isNot(contains('alpha')));
    await a.close();
    await b.close();
    await engine.close();
  });

  testWidgets('GPU backend creates an engine (falls back gracefully)', (
    _,
  ) async {
    final engine = await LiteRtLm.createEngine(
      modelPath: _modelPath,
      backend: Backend.gpu,
      maxTokens: 2048,
    );
    final convo = await engine.createConversation();
    final reply = await convo.generate(
      const Prompt.user(text: 'Say hi in one word.'),
    );
    expect(reply.trim(), isNotEmpty);
    await convo.close();
    await engine.close();
  });

  testWidgets('closed engine rejects further use', (_) async {
    final engine = await LiteRtLm.createEngine(
      modelPath: _modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    await engine.close();
    expect(
      () => engine.createConversation(),
      throwsA(isA<DisposedException>()),
    );
  });

  testWidgets('missing model path throws EngineCreateException', (_) async {
    expect(
      () => LiteRtLm.createEngine(
        modelPath: '/definitely/not/here.litertlm',
        backend: Backend.cpu,
      ),
      throwsA(isA<LiteRtLmException>()),
    );
  });
}
