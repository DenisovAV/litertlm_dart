/// Low-level entrypoint: the raw ffigen bindings to the LiteRT-LM C API.
///
/// NO stability guarantees — these mirror `native/litert_lm/include/engine.h`
/// and change whenever the native header does. Use `package:litertlm_dart/
/// litertlm_dart.dart` for the stable, typed runtime API. This entrypoint
/// exists for consumers that need direct C-API access the typed layer doesn't
/// expose.
library;

export 'src/bindings/litert_lm_bindings.dart';
