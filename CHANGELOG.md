# Changelog

## 0.1.1

- Trim the package description to pub.dev's 60–180 character range.
- Add `example/README.md` so the example is discovered by pub.dev / pana.

## 0.1.0

First runtime release — the LiteRT-LM engine extracted from `flutter_gemma_litertlm`.

- Typed `Engine` → `Conversation` → `Stream<String>` API over the LiteRT-LM C API.
- Native prebuilts for all five targets (Android, iOS, macOS, Windows, Linux) via a Native Assets build hook; SHA256-verified.
- CPU / GPU / NPU backend selection, with an optional separate vision backend.
- Multimodal prompts (image / audio) for capable models; `maxOutputTokens` reply cap; cancellable streaming.
- Typed exception hierarchy; pluggable native-library resolution (Native Assets for apps, directory-based for CLI/server).
- Raw C-API bindings exported via `package:litertlm_dart/bindings.dart`.
- Verified end-to-end on all five platforms with Gemma 4 E2B.

## 0.0.1

- Name-holding release: package scope, roadmap, and target LiteRT-LM version.
