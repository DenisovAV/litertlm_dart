import 'package:meta/meta.dart';

/// Inference accelerator selection.
///
/// Typed replacement for the string-based `backend_str` of the original
/// flutter_gemma_litertlm client. `npu` requires platform prerequisites
/// (Qualcomm QNN dispatch on Android, Intel NPU dispatch on Windows) bundled
/// with the native prebuilts.
enum Backend {
  cpu,
  gpu,
  npu;

  /// The lowercase string the native C API expects as `backend_str`.
  ///
  /// Internal: consumers select a backend with the enum, never the wire
  /// string — keeping this out of the public contract lets the enum→string
  /// mapping evolve without a breaking change.
  @internal
  String get wireName => name;
}
