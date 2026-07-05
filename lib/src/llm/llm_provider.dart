import 'llm_message.dart';

/// Abstract interface for any LLM provider.
///
/// Implementations can be swapped in at runtime, making the whole system
/// provider-agnostic.
abstract class LlmProvider {
  String get defaultModel;

  /// Send a single user prompt and return the generated text.
  ///
  /// [onCancel] is invoked by the provider if the call times out or is
  /// interrupted, giving the caller a chance to call provider-specific cancel
  /// logic (e.g. WebLLM interruptGenerate).
  Future<String> chat(String prompt, {String? model, void Function()? onCancel});

  /// Send a conversation and return the generated text.
  Future<String> chatMessages(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  });
}
