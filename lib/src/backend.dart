/// Inference accelerator selection.
///
/// Typed replacement for the string-based `backend_str` of the original
/// flutter_gemma_litertlm client. `npu` requires platform prerequisites
/// (Qualcomm QNN dispatch on Android, Intel NPU dispatch on Windows) bundled
/// with the native prebuilts.
enum Backend { cpu, gpu, npu }
