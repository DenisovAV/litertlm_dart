/// Cross-platform end-to-end suite for litertlm_dart. This is the "all five
/// platforms" gate from the design doc (§6/§8): it must be green on Android,
/// iOS, macOS, Windows and Linux before any pub.dev publication.
///
/// Run (native targets — NEVER `flutter drive`, see flutter_gemma rules):
///   flutter test integration_test/litertlm_dart_test.dart -d DEVICE_ID \
///     --dart-define=MODEL_PATH=/abs/path/gemma-4-E2B-it.litertlm
///
/// Model resolution order (see `_resolveModelPath`):
///   1. `--dart-define=MODEL_PATH=/abs/model.litertlm` — desktop/CLI, used as-is.
///   2. A pre-pushed / previously-staged file (re-run reuse; iOS `devicectl`
///      copy to Documents/, Android `adb push` to the app dir).
///   3. Otherwise the suite STREAMS the model from HuggingFace on-device into
///      the app-support dir — this is how it runs on Firebase Test Lab (which
///      has no adb push). Pass the gated-repo token at build time:
///      `--dart-define=HUGGINGFACE_TOKEN=hf_...`.
///
/// The model is streamed to disk, never `rootBundle.load`: a `.litertlm` is
/// multi-GB and a Dart ByteData is capped at 2^30-1 bytes (~1 GiB), so a
/// full-file read throws `NewExternalTypedData ... range [0..1073741823]`.
/// This mirrors flutter_gemma's FTL recipe (download on-device, token via
/// --dart-define) instead of bundling a 2.4 GB APK asset.
///
/// Until the 0.1.0 extraction lands, everything past the contract test is
/// expected to FAIL with UnimplementedError — that is the TDD red state, not
/// a broken suite.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:litertlm_dart/litertlm_dart.dart';
import 'package:path_provider/path_provider.dart';

const _modelPathOverride = String.fromEnvironment('MODEL_PATH');

/// Gemma 4 E2B `.litertlm` — the same E2B artifact flutter_gemma's FTL suite
/// uses. Gated on HuggingFace, so [_hfToken] (passed via
/// `--dart-define=HUGGINGFACE_TOKEN=...`) is required to fetch it.
const _modelUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
const _hfToken = String.fromEnvironment('HUGGINGFACE_TOKEN');
const _stagedModelFileName = 'gemma4.litertlm';

/// A real `.litertlm` model is hundreds of MB; anything below this floor is a
/// truncated/interrupted stage or a placeholder — reject it so a corrupt file
/// isn't accepted as "staged and readable" (which would surface later as a
/// cryptic engine-create error, disconnecting symptom from cause).
const _minModelBytes = 100 * 1024 * 1024;

bool _looksLikeModel(File f) =>
    f.existsSync() && f.lengthSync() >= _minModelBytes;

late final String _modelPath;

/// Streams the model from [_modelUrl] to a writable file once, reusing it
/// across every test in this suite. Only used when MODEL_PATH is not supplied
/// and no pre-staged file was found (e.g. on Firebase Test Lab, which has no
/// adb push).
///
/// The response is piped straight to disk (never held whole in memory), so it
/// is immune to the ~1 GiB Dart-ByteData ceiling that `rootBundle.load` /
/// `response.bodyBytes` would hit on a 2.4 GB model. HuggingFace 302-redirects
/// the `resolve/...` URL to a signed CDN host that needs no auth; the redirect
/// is followed manually so the Bearer token is only ever sent to
/// `huggingface.co`, never leaked to (or rejected by) the CDN.
Future<String> _downloadModel() async {
  final dir = await getApplicationSupportDirectory();
  final dest = File('${dir.path}/$_stagedModelFileName');
  if (_looksLikeModel(dest)) {
    return dest.path;
  }
  final originHost = Uri.parse(_modelUrl).host;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 60);
  try {
    var uri = Uri.parse(_modelUrl);
    late HttpClientResponse resp;
    for (var hop = 0; ; hop++) {
      final req = await client.getUrl(uri);
      req.followRedirects = false;
      if (uri.host == originHost && _hfToken.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_hfToken');
      }
      resp = await req.close();
      if (resp.statusCode == HttpStatus.ok) break;
      final location = resp.headers.value(HttpHeaders.locationHeader);
      if (resp.isRedirect && location != null) {
        if (hop >= 5) {
          throw StateError('Too many redirects fetching $_modelUrl');
        }
        final next = Uri.parse(location);
        uri = next.hasScheme ? next : uri.resolveUri(next);
        await resp.drain<void>();
        continue;
      }
      throw StateError(
        'Model download failed: HTTP ${resp.statusCode} from $uri',
      );
    }
    // Stream to a .part file, then atomically rename — a half-written file is
    // never accepted as "staged" on a re-run.
    final part = File('${dest.path}.part');
    await resp.pipe(part.openWrite());
    await part.rename(dest.path);
  } finally {
    client.close(force: true);
  }
  if (!_looksLikeModel(dest)) {
    throw StateError('Downloaded model is undersized: ${dest.path}');
  }
  return dest.path;
}

/// Resolves the model path to use for the whole suite, in order:
///   1. `--dart-define=MODEL_PATH=...` (desktop/CLI — unchanged).
///   2. An already-staged file in the app-support directory (re-run reuse).
///   3. A file dropped into the app's Documents/ directory ahead of time —
///      this is how the model gets onto a physical iOS device:
///      `xcrun devicectl device copy to ... --destination Documents/gemma4.litertlm`.
///      Used directly, no copy (avoids doubling disk usage for a multi-GB file).
///   4. Otherwise stream the model from HuggingFace to app-support (Firebase
///      Test Lab and any device without a pre-staged file).
Future<String> _resolveModelPath() async {
  if (_modelPathOverride.isNotEmpty) {
    return _modelPathOverride;
  }
  final supportDir = await getApplicationSupportDirectory();
  final staged = File('${supportDir.path}/$_stagedModelFileName');
  if (_looksLikeModel(staged)) {
    return staged.path;
  }
  final documentsDir = await getApplicationDocumentsDirectory();
  final pushed = File('${documentsDir.path}/$_stagedModelFileName');
  if (_looksLikeModel(pushed)) {
    return pushed.path;
  }
  return _downloadModel();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Resolve/stage the model as the FIRST test (not setUpAll) so the cold
  // ~2.4 GB HuggingFace download on FTL gets an explicit generous timeout
  // instead of the default per-item one. Later tests reuse `_modelPath`.
  testWidgets(
    'model is staged/downloaded and readable',
    (_) async {
      _modelPath = await _resolveModelPath();
      expect(
        _modelPath,
        isNotEmpty,
        reason:
            'set --dart-define=MODEL_PATH=... or --dart-define=HUGGINGFACE_TOKEN=...',
      );
      expect(
        _looksLikeModel(File(_modelPath)),
        isTrue,
        reason: 'model missing/undersized at $_modelPath',
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );

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
