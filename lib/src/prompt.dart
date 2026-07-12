import 'dart:typed_data';

/// One user turn of input to [Conversation.generateStream]: text plus
/// optional image/audio payloads (for models and engine configurations that
/// support them).
///
/// Typed replacement for the hand-built JSON strings of the original client
/// (`buildMessageJson`) — the JSON marshalling to the C API is a package
/// internal.
///
/// ORDERING: the native runtime currently lays out content as text first,
/// then the media payloads — it does not support arbitrary interleaving of
/// text and images within one turn. The flat `text` / `images` / `audio`
/// shape reflects that. A richer ordered content-parts API may be added
/// additively if/when the native layer supports interleaving; until then a
/// parts API would expose an ordering the runtime cannot honor.
class Prompt {
  /// A user turn. [text] defaults to empty so an image-only prompt needs no
  /// placeholder string.
  const Prompt.user({this.text = '', this.images = const [], this.audio});

  final String text;

  /// Raw encoded image bytes (PNG/JPEG), one entry per image. Appended after
  /// [text] in the native message (see the ORDERING note above).
  final List<Uint8List> images;

  /// Raw audio payload, when the engine was created with audio support.
  final Uint8List? audio;

  bool get isMultimodal => images.isNotEmpty || audio != null;
}
