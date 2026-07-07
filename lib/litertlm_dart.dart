/// Pure Dart runtime for Google's LiteRT-LM.
///
/// 0.0.x ships the typed API contract (`LiteRtLm.createEngine` →
/// `Engine` → `Conversation` → `Stream<String>`); the battle-tested FFI
/// implementation extracted from `flutter_gemma_litertlm` lands in 0.1.0 —
/// see `docs/design/2026-07-07-litertlm-dart-design.md`.
library;

export 'src/backend.dart';
export 'src/conversation.dart';
export 'src/engine.dart';
export 'src/exceptions.dart';
export 'src/library_locator.dart';
export 'src/log_sink.dart';
export 'src/prompt.dart';

/// The version of the LiteRT-LM native prebuilts this package targets.
const String targetLiteRtLmVersion = '0.13.1';
