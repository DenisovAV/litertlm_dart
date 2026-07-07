import 'dart:typed_data';

/// One user turn of input to [Conversation.generateStream]: text plus
/// optional image/audio payloads (for models and engine configurations that
/// support them).
///
/// Typed replacement for the hand-built JSON strings of the original client
/// (`buildMessageJson`) — the JSON marshalling to the C API is a package
/// internal.
class Prompt {
  const Prompt.user({required this.text, this.images = const [], this.audio});

  final String text;

  /// Raw encoded image bytes (PNG/JPEG), one entry per image.
  final List<Uint8List> images;

  /// Raw audio payload, when the engine was created with audio support.
  final Uint8List? audio;

  bool get isMultimodal => images.isNotEmpty || audio != null;
}
