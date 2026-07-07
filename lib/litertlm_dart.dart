/// Pure Dart runtime for Google's LiteRT-LM.
///
/// This is an early name-holding release while the package is under active
/// development. The 0.1.0 release will provide:
///
/// * FFI bindings to the LiteRT-LM C API (all desktop + mobile platforms),
/// * a typed `Engine` → `Conversation` → `Stream<String>` inference API
///   with CPU / GPU / NPU backend selection,
/// * multimodal (vision / audio) prompt input,
/// * pluggable native-library resolution for CLI, server, and Flutter use.
///
/// The battle-tested implementation is being extracted from
/// `flutter_gemma_litertlm` (pub.dev/packages/flutter_gemma_litertlm), which
/// will become a thin Flutter adapter over this package.
library;

/// The version of the LiteRT-LM native prebuilts this package targets.
///
/// Placeholder surface for the 0.0.x name-holding releases; the real API
/// lands in 0.1.0 (see the library docs above).
const String targetLiteRtLmVersion = '0.13.1';
