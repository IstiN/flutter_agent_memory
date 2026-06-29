@Tags(['integration'])

import 'package:flutter_agent_memory/src/llm/openai_provider.dart';
import 'package:test/test.dart';

import 'ollama_config.dart';

void main() {
  late final OllamaConfig config;

  setUpAll(() {
    config = OllamaConfig.load();
  });

  test('Ollama chat completions return a non-empty response', () async {
    if (!config.configured) {
      markTestSkipped('Ollama config not available');
      return;
    }

    final provider = OpenAiProvider(
      apiKey: config.apiKey,
      baseUrl: config.baseUrl,
      defaultModel: config.model,
      maxTokens: 64,
      temperature: 0,
    );

    final response = await provider.chat('Reply with exactly one word: hello.');
    expect(response.trim(), isNotEmpty);
    expect(response.trim().length, greaterThan(1));
  }, timeout: const Timeout(Duration(seconds: 120)));
}
