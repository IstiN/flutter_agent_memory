@Tags(['integration'])
import 'dart:io';

import 'package:flutter_agent_memory/src/core/kb_orchestrator.dart';
import 'package:flutter_agent_memory/src/core/kb_orchestrator_params.dart';
import 'package:flutter_agent_memory/src/llm/openai_provider.dart';
import 'package:flutter_agent_memory/src/models/kb_processing_mode.dart';
import 'package:flutter_agent_memory/src/search/kb_search_engine.dart';
import 'package:test/test.dart';

import 'ollama_config.dart';

void main() {
  late final OllamaConfig config;

  setUpAll(() {
    config = OllamaConfig.load();
  });

  test(
    'builds KB from rich transcript and searches via generated tags',
    () async {
      if (!config.configured) {
        markTestSkipped('Ollama config not available');
        return;
      }

      final outputDir = Directory.systemTemp.createTempSync('ollama_search_');
      addTearDown(() => outputDir.deleteSync(recursive: true));
      print('KB output directory: ${outputDir.absolute.path}');

      final provider = OpenAiProvider(
        apiKey: config.apiKey,
        baseUrl: config.baseUrl,
        defaultModel: config.model,
        maxTokens: 4096,
        temperature: 0,
      );

      final transcript =
          '''
[2024-11-15T09:00:00Z] Alice: What is the best way to manage state in Flutter?
[2024-11-15T09:02:00Z] Bob: Use Riverpod or Bloc. Riverpod is simpler for small apps, Bloc is great for complex business logic.

[2024-11-15T09:10:00Z] Alice: How do I write unit tests in Dart?
[2024-11-15T09:12:00Z] Charlie: Use the test package. Group tests with group() and write assertions with expect().

[2024-11-15T09:20:00Z] Alice: How do I build a Docker image for a Dart backend?
[2024-11-15T09:25:00Z] Bob: Use a multi-stage Dockerfile. Start from dart:stable, build the AOT snapshot, then copy it into a small runtime image.

[2024-11-15T09:30:00Z] Alice: What CI/CD tool do you recommend for Flutter apps?
[2024-11-15T09:32:00Z] Charlie: GitHub Actions works well. Use actions/checkout, install Flutter, and run flutter test and flutter build.

[2024-11-15T09:40:00Z] Alice: How do I handle async data loading in Flutter widgets?
[2024-11-15T09:42:00Z] Bob: Use FutureBuilder or StreamBuilder, or wrap the logic with a state management solution like Riverpod.
'''
              .trim();

      final orchestrator = KBOrchestrator(provider);
      final buildResult = await orchestrator.run(
        KBOrchestratorParams(
          sourceName: 'integration_search_test',
          inputText: transcript,
          outputPath: outputDir.path,
          processingMode: KBProcessingMode.processOnly,
          analysisExtraInstructions:
              'Extract all clear questions and answers. Preserve the topic area and 1-3 specific topics for each record.',
        ),
      );

      expect(buildResult.success, isTrue);
      expect(buildResult.questionsCount, greaterThanOrEqualTo(3));
      expect(buildResult.answersCount, greaterThanOrEqualTo(3));

      final engine = KBSearchEngine.file(outputDir, provider: provider);

      final searchQueries = [
        _SearchExpectation(
          query: 'How do I manage state in Flutter?',
          expectedKeywordsInTags: ['flutter', 'state'],
          expectedResultKeywordsInTitle: ['state', 'riverpod', 'bloc'],
        ),
        _SearchExpectation(
          query: 'Dart unit testing',
          expectedKeywordsInTags: [
            'dart',
            'test',
            'unit-testing',
            'test-package',
          ],
          expectedResultKeywordsInTitle: ['test', 'unit'],
        ),
        _SearchExpectation(
          query: 'Docker image for Dart',
          expectedKeywordsInTags: ['docker', 'dart'],
          expectedResultKeywordsInTitle: ['docker', 'image', 'dart'],
        ),
        _SearchExpectation(
          query: 'CI/CD for Flutter',
          expectedKeywordsInTags: [
            'ci',
            'ci/cd',
            'flutter',
            'github',
            'github-actions',
          ],
          expectedResultKeywordsInTitle: ['ci', 'github', 'flutter'],
        ),
      ];

      for (final expectation in searchQueries) {
        print('Searching: "${expectation.query}"');
        final result = await engine.searchByText(
          expectation.query,
          matchAll: false,
          maxGeneratedTags: 6,
        );

        print('  Generated tags: ${result.generatedTags}');
        print('  Results count: ${result.results.length}');

        expect(
          result.generatedTags,
          isNotEmpty,
          reason:
              'Query "${expectation.query}" should generate at least one tag',
        );

        final lowerTags = result.generatedTags
            .map((t) => t.toLowerCase())
            .toSet();
        expect(
          expectation.expectedKeywordsInTags.any(lowerTags.contains),
          isTrue,
          reason:
              'Expected at least one of ${expectation.expectedKeywordsInTags} in generated tags, got $lowerTags',
        );

        expect(
          result.results,
          isNotEmpty,
          reason:
              'Query "${expectation.query}" should return at least one record',
        );

        final titles = result.results
            .map((r) => (r.title ?? '').toLowerCase())
            .toList();
        expect(
          titles.any(
            (title) =>
                expectation.expectedResultKeywordsInTitle.any(title.contains),
          ),
          isTrue,
          reason:
              'Expected one of the results to mention ${expectation.expectedResultKeywordsInTitle}, got $titles',
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 300)),
  );
}

class _SearchExpectation {
  final String query;
  final List<String> expectedKeywordsInTags;
  final List<String> expectedResultKeywordsInTitle;

  _SearchExpectation({
    required this.query,
    required this.expectedKeywordsInTags,
    required this.expectedResultKeywordsInTitle,
  });
}
