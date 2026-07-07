import 'dart:io';
import 'dart:typed_data';

import 'package:litertlm_dart/litertlm_dart.dart';
import 'package:test/test.dart';

void main() {
  test('declares the targeted native LiteRT-LM version', () {
    expect(targetLiteRtLmVersion, isNotEmpty);
  });

  group('LibraryLocator', () {
    test('fromDirectory builds platform-correct paths', () {
      final l = LibraryLocator.fromDirectory('/opt/litertlm');
      if (Platform.isMacOS) {
        expect(l.mainLibraryPath, '/opt/litertlm/libLiteRtLm.dylib');
        expect(l.proxyLibraryPath, '/opt/litertlm/libStreamProxy.dylib');
      } else if (Platform.isWindows) {
        expect(l.mainLibraryPath, r'/opt/litertlm\LiteRtLm.dll');
      } else {
        expect(l.mainLibraryPath, '/opt/litertlm/libLiteRtLm.so');
      }
    });

    test('fromDirectory tolerates a trailing separator', () {
      final sep = Platform.pathSeparator;
      final a = LibraryLocator.fromDirectory('${sep}opt${sep}x$sep');
      final b = LibraryLocator.fromDirectory('${sep}opt${sep}x');
      expect(a.mainLibraryPath, b.mainLibraryPath);
    });

    test('custom passes paths through untouched', () {
      const l = LibraryLocator.custom(
        mainLibraryPath: 'a/b/main.so',
        proxyLibraryPath: 'a/b/proxy.so',
      );
      expect(l.mainLibraryPath, 'a/b/main.so');
      expect(l.proxyLibraryPath, 'a/b/proxy.so');
    });

    test('defaultForPlatform resolves without touching the filesystem', () {
      final l = LibraryLocator.defaultForPlatform();
      expect(l.mainLibraryPath, isNotEmpty);
      expect(l.proxyLibraryPath, isNotEmpty);
    });
  });

  group('Prompt', () {
    test('text-only prompt is not multimodal', () {
      const p = Prompt.user(text: 'hi');
      expect(p.isMultimodal, isFalse);
    });

    test('images make a prompt multimodal', () {
      final p = Prompt.user(text: 'what is this?', images: [Uint8List(4)]);
      expect(p.isMultimodal, isTrue);
    });

    test('audio makes a prompt multimodal', () {
      final p = Prompt.user(text: 'transcribe', audio: Uint8List(4));
      expect(p.isMultimodal, isTrue);
    });
  });

  group('exceptions', () {
    test('carry their message in toString', () {
      expect(
        GenerationException('stream broke').toString(),
        contains('stream broke'),
      );
    });

    test('LibraryLoadException records attempted paths', () {
      final e = LibraryLoadException('nope', attemptedPaths: ['/a', '/b']);
      expect(e.attemptedPaths, hasLength(2));
    });

    test('EngineCreateException carries the native log tail', () {
      final e = EngineCreateException('boom', nativeLogTail: 'glog says hi');
      expect(e.nativeLogTail, contains('glog'));
    });
  });

  test('createEngine is contract-only in 0.0.x', () {
    expect(
      () => LiteRtLm.createEngine(modelPath: '/tmp/x.litertlm'),
      throwsUnimplementedError,
    );
  });
}
