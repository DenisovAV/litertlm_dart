// CLI smoke for litertlm_dart — proves the runtime works with ZERO Flutter.
//
// Usage:
//   dart run example/cli/bin/generate.dart <model.litertlm> [prompt] \
//     [--libs=/dir/with/dylibs] [--backend=cpu|gpu]
//
// The native prebuilts are resolved two ways:
//   1. --libs=<dir>  → LibraryLocator.fromDirectory (explicit, always works).
//   2. otherwise      → LibraryLocator.defaultForPlatform() (Native Assets /
//      loader search path — needs the hook to have run for this package).
//
// On a dev machine the simplest path is (1) pointed at the flutter_gemma
// native cache, e.g. ~/Library/Caches/flutter_gemma/native/macos_arm64.
import 'dart:io';

import 'package:litertlm_dart/litertlm_dart.dart';

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run generate.dart <model.litertlm> [prompt] '
      '[--libs=/dir] [--backend=cpu|gpu]',
    );
    exitCode = 64;
    return;
  }
  final modelPath = positional[0];
  final prompt = positional.length > 1
      ? positional[1]
      : 'Reply with exactly one word: hello';

  final libsArg = _flag(args, '--libs');
  final backend = switch (_flag(args, '--backend')) {
    'gpu' => Backend.gpu,
    'npu' => Backend.npu,
    _ => Backend.cpu,
  };

  final libraries = libsArg != null
      ? LibraryLocator.fromDirectory(libsArg)
      : LibraryLocator.defaultForPlatform();

  stdout.writeln(
    'litertlm_dart CLI · backend=${backend.name} '
    '· libs=${libsArg ?? 'default'}',
  );
  stdout.writeln('loading $modelPath …');

  final engine = await LiteRtLm.createEngine(
    modelPath: modelPath,
    backend: backend,
    maxTokens: 2048,
    libraries: libraries,
    // Keep native stderr OFF the redirect so this CLI's own stdout (the
    // model's reply) reaches the console instead of a temp log file.
    captureNativeLog: false,
    log: silentLogSink,
  );
  stdout.writeln('engine ready. prompt: "$prompt"\n---');

  final convo = await engine.createConversation();
  await for (final chunk in convo.generateStream(Prompt.user(text: prompt))) {
    stdout.write(chunk);
  }
  stdout.writeln('\n---');

  await convo.close();
  await engine.close();
  stdout.writeln('done.');
}

String? _flag(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}
