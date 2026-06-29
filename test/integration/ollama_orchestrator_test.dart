@Tags(['integration'])

import 'dart:io';

import 'package:flutter_agent_memory/src/core/kb_orchestrator.dart';
import 'package:flutter_agent_memory/src/core/kb_orchestrator_params.dart';
import 'package:flutter_agent_memory/src/llm/openai_provider.dart';
import 'package:flutter_agent_memory/src/models/kb_processing_mode.dart';
import 'package:test/test.dart';

import 'ollama_config.dart';

void main() {
  late final OllamaConfig config;

  setUpAll(() {
    config = OllamaConfig.load();
  });

  test('full orchestrator pipeline produces KB files', () async {
    if (!config.configured) {
      markTestSkipped('Ollama config not available');
      return;
    }

    final outputDir = Directory('test_output/ollama_kb');
    if (outputDir.existsSync()) outputDir.deleteSync(recursive: true);
    outputDir.createSync(recursive: true);
    print('KB output directory: ${outputDir.absolute.path}');
    addTearDown(() {
      if (Platform.environment['KEEP_OUTPUT'] != 'true') {
        outputDir.deleteSync(recursive: true);
      }
    });

    final provider = OpenAiProvider(
      apiKey: config.apiKey,
      baseUrl: config.baseUrl,
      defaultModel: config.model,
      maxTokens: 2048,
      temperature: 0,
    );

    final orchestrator = KBOrchestrator(provider);
    final result = await orchestrator.run(KBOrchestratorParams(
      sourceName: 'integration_test',
      inputText: '''
[2024-11-15T09:30:00Z] Alice: How do I write unit tests in Dart?
[2024-11-15T09:32:00Z] Bob: Use the test package and group your tests with group() and test().
''',
      outputPath: outputDir.path,
      processingMode: KBProcessingMode.processOnly,
      analysisExtraInstructions: 'Be concise. Extract exactly one question and one answer.',
    ));

    expect(result.success, isTrue);
    expect(result.questionsCount, greaterThanOrEqualTo(1));
    expect(result.answersCount, greaterThanOrEqualTo(1));

    expect(File('${outputDir.path}/questions/q_0001.md').existsSync(), isTrue);
    expect(File('${outputDir.path}/answers/a_0001.md').existsSync(), isTrue);
    expect(File('${outputDir.path}/INDEX.md').existsSync(), isTrue);
  }, timeout: const Timeout(Duration(seconds: 180)));
}
