// Standalone on-device runner for the 9 gate checks — a workaround for the
// iOS 26 `flutter test` mDNS VM-Service-discovery failure on this device.
// It runs the same assertions as integration_test/litertlm_dart_test.dart but
// as plain code, launched via `xcrun devicectl device process launch` (no VM
// Service needed), and writes PASS/FAIL to Documents/ios_gate_result.txt
// (pulled from the host afterwards) as well as to the screen.
//
// Model: read in place from Documents/gemma4.litertlm (pushed via devicectl).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:litertlm_dart/litertlm_dart.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final log = ValueNotifier<String>('Starting iOS gate…\n');
  final docs = await getApplicationDocumentsDirectory();
  final out = File('${docs.path}/ios_gate_result.txt')..writeAsStringSync('');
  var passed = 0;
  var failed = 0;

  void line(String s) {
    log.value = '${log.value}$s\n';
    out.writeAsStringSync('$s\n', mode: FileMode.append, flush: true);
  }

  Future<void> check(String name, Future<void> Function() body) async {
    try {
      await body();
      passed++;
      line('PASS  $name');
    } catch (e) {
      failed++;
      line('FAIL  $name  -> $e');
    }
  }

  runApp(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ValueListenableBuilder<String>(
              valueListenable: log,
              builder: (_, v, _) => Text(
                v,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontFamily: 'Menlo',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  final modelPath = '${docs.path}/gemma4.litertlm';
  line(
    'model: $modelPath (${File(modelPath).existsSync() ? "${File(modelPath).lengthSync() ~/ (1024 * 1024)} MB" : "MISSING"})',
  );
  line('─── running 9 checks ───');

  await check('MODEL_PATH is staged and readable', () async {
    if (!File(modelPath).existsSync()) throw StateError('missing');
  });

  await check('engine creates and closes (CPU)', () async {
    final e = await LiteRtLm.createEngine(
      modelPath: modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    if (e.activeConversations != 0) throw StateError('nonzero convos');
    await e.close();
  });

  await check('streams a reply to completion', () async {
    final e = await LiteRtLm.createEngine(
      modelPath: modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    final c = await e.createConversation();
    final chunks = <String>[];
    await for (final ch in c.generateStream(
      const Prompt.user(text: 'Say hello.'),
    )) {
      chunks.add(ch);
    }
    line('   streamed ${chunks.length} chunks: "${chunks.join().trim()}"');
    await c.close();
    await e.close();
  });

  await check('conversation keeps history across turns', () async {
    final e = await LiteRtLm.createEngine(
      modelPath: modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    final c = await e.createConversation();
    await c.generate(
      const Prompt.user(text: 'My name is Kestrel. Remember it.'),
    );
    final r = await c.generate(
      const Prompt.user(text: 'What is my name? Answer with the name only.'),
    );
    line('   reply: "${r.trim()}"');
    if (!r.toLowerCase().contains('kestrel')) throw StateError('no kestrel');
    await c.close();
    await e.close();
  });

  await check('maxOutputTokens caps the reply length', () async {
    final e = await LiteRtLm.createEngine(
      modelPath: modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    final c = await e.createConversation(maxOutputTokens: 8);
    final r = await c.generate(
      const Prompt.user(text: 'Count from one to one hundred in words.'),
    );
    if (r.length >= 200) throw StateError('too long: ${r.length}');
    await c.close();
    await e.close();
  });

  await check('cancel interrupts an in-flight generation', () async {
    final e = await LiteRtLm.createEngine(
      modelPath: modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    final c = await e.createConversation();
    final received = <String>[];
    final done = c
        .generateStream(
          const Prompt.user(text: 'Write a very long story about the sea.'),
        )
        .listen(received.add)
        .asFuture<void>()
        .catchError((_) {});
    await Future<void>.delayed(const Duration(seconds: 2));
    c.cancel();
    await done.timeout(const Duration(seconds: 15));
    await c.close();
    await e.close();
  });

  await check('two conversations are isolated', () async {
    final e = await LiteRtLm.createEngine(
      modelPath: modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    final a = await e.createConversation();
    final b = await e.createConversation();
    if (e.activeConversations != 2) throw StateError('count');
    await a.generate(const Prompt.user(text: 'My name is Alpha.'));
    final r = await b.generate(
      const Prompt.user(
        text: 'Do you know my name? Answer yes or no, one word.',
      ),
    );
    if (r.toLowerCase().contains('alpha')) throw StateError('leaked');
    await a.close();
    await b.close();
    await e.close();
  });

  await check(
    'GPU backend creates an engine (falls back gracefully)',
    () async {
      final e = await LiteRtLm.createEngine(
        modelPath: modelPath,
        backend: Backend.gpu,
        maxTokens: 2048,
      );
      final c = await e.createConversation();
      final r = await c.generate(
        const Prompt.user(text: 'Say hi in one word.'),
      );
      if (r.trim().isEmpty) throw StateError('empty');
      await c.close();
      await e.close();
    },
  );

  await check('closed engine rejects further use', () async {
    final e = await LiteRtLm.createEngine(
      modelPath: modelPath,
      backend: Backend.cpu,
      maxTokens: 2048,
    );
    await e.close();
    try {
      await e.createConversation();
      throw StateError('should have thrown');
    } on DisposedException {
      // expected
    }
  });

  line('─── DONE: $passed passed, $failed failed ───');
}
