import 'dart:convert';

import 'package:flutter_agent_memory/src/llm/llm_message.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';

/// A fake LLM provider for tests that returns pre-programmed responses.
class FakeLlmProvider implements LlmProvider {
  final Map<String, String> _responses;

  FakeLlmProvider(this._responses);

  @override
  String get defaultModel => 'fake-model';

  @override
  Future<String> chat(String prompt, {String? model}) async {
    return _match(prompt);
  }

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) async {
    return _match(messages.map((m) => m.content).join('\n'));
  }

  String _match(String prompt) {
    for (final entry in _responses.entries) {
      if (entry.key.isEmpty || prompt.contains(entry.key)) return entry.value;
    }
    return _responses.values.isNotEmpty
        ? _responses.values.first
        : jsonEncode({
            'questions': [],
            'answers': [],
            'notes': [],
          });
  }
}
