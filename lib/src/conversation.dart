import 'prompt.dart';

/// One dialogue with the model: history is accumulated natively between
/// [generateStream] calls.
abstract interface class Conversation {
  /// Streams the model's reply to [prompt], token chunk by token chunk.
  ///
  /// The returned stream is single-subscription; errors surface as
  /// [GenerationException]. A [cancel] call ends the stream early with
  /// whatever was generated.
  Stream<String> generateStream(Prompt prompt);

  /// Convenience: [generateStream] joined to one string.
  Future<String> generate(Prompt prompt);

  /// Interrupts an in-flight generation. Safe to call when idle.
  void cancel();

  /// Releases the native conversation. The object is unusable afterwards.
  Future<void> close();
}
