import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:integration_test/integration_test.dart';

import 'package:demo/llm/gemma_llm_provider.dart';
import 'package:demo/services/gemma_model_presets.dart';
import 'package:demo/services/gemma_service.dart';
import 'package:demo/services/prompt_asset_loader.dart';

/// Reusable benchmark input and validation expectations.
class _BenchmarkCase {
  final String name;
  final String transcript;
  final int minQuestions;
  final int minAnswers;
  final List<_SearchExpectation> searchQueries;

  _BenchmarkCase({
    required this.name,
    required this.transcript,
    required this.minQuestions,
    required this.minAnswers,
    required this.searchQueries,
  });
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

/// Runs the same KB orchestrator/search integration case against every
/// installed local Flutter Gemma model to compare capability and reliability.
///
/// Each model is exercised with the same input transcript and the same
/// assertions, using its full spec context window with maxOutputTokens set to
/// maxTokens ~/ 2.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  initializePromptAssetLoader();

  final cases = <_BenchmarkCase>[
    _BenchmarkCase(
      name: 'rich transcript',
      transcript: '''
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
'''.trim(),
      minQuestions: 3,
      minAnswers: 3,
      searchQueries: [
        _SearchExpectation(
          query: 'How do I manage state in Flutter?',
          expectedKeywordsInTags: ['flutter', 'state', 'state-management'],
          expectedResultKeywordsInTitle: ['state', 'riverpod', 'bloc'],
        ),
        _SearchExpectation(
          query: 'Dart unit testing',
          expectedKeywordsInTags: ['dart', 'test', 'unit-testing'],
          expectedResultKeywordsInTitle: ['test', 'unit'],
        ),
        _SearchExpectation(
          query: 'Docker image for Dart',
          expectedKeywordsInTags: ['docker', 'dart'],
          expectedResultKeywordsInTitle: ['docker', 'image', 'dart'],
        ),
        _SearchExpectation(
          query: 'CI/CD for Flutter',
          expectedKeywordsInTags: ['ci', 'ci/cd', 'flutter', 'github'],
          expectedResultKeywordsInTitle: ['ci', 'github', 'flutter'],
        ),
      ],
    ),
  ];

  // Desktop-compatible .litertlm presets that are present in the local gallery.
  // functiongemma-270m is omitted because it emits only <pad> tokens for this
  // JSON-extraction task and would hit the per-test timeout without producing
  // useful output.
  final modelConfigs = <({String id, GemmaModelPreset Function(GemmaModelPreset) override})>[
    // Baseline Gemma 4 .litertlm (already verified).
    (id: 'gemma4-e2b-litertlm', override: _defaultOverride),
    // Context-window experiment for the current .litertlm build: ask the
    // runtime for a larger window and see whether it accepts it or falls back.
    (
      id: 'gemma4-e2b-litertlm',
      override: (base) => _defaultOverride(base).copyWith(
        id: 'gemma4-e2b-litertlm-x2',
        maxTokens: 8192,
        maxOutputTokens: 4096,
      ),
    ),
    // MediaPipe/web .task variant with a much larger baked-in context window.
    (
      id: 'gemma4-e2b',
      override: (base) => _defaultOverride(base).copyWith(
        id: 'gemma4-e2b-web',
        maxTokens: 65536,
        maxOutputTokens: 32768,
      ),
    ),
  ];

  group('KB model benchmark', () {
    for (final config in modelConfigs) {
      final basePreset = findGemmaPreset(config.id);
      if (basePreset == null) continue;

      // Use the model's full context window, but reserve half for output so we
      // don't exceed the baked-in kv-cache size. Lock temperature to 0 so the
      // benchmark is deterministic and local models stay as close to the prompt
      // instructions as possible.
      //
      // Phi-4 Mini's .litertlm build fails to initialize on the Metal backend on
      // some Apple Silicon configs, so we run it on CPU to get a comparable
      // result instead of a hard GPU-load failure.
      final preset = config.override(basePreset);

      testWidgets(
        '${preset.id}: ${cases.map((c) => c.name).join(', ')}',
        (tester) async {
          final service = FlutterGemmaService();
          await service.initialize();

          if (!await service.isModelInstalled(preset)) {
            print('[ModelBench] Downloading ${preset.displayName} (${preset.size})...');
            await for (final progress in service.installModel(preset)) {
              print('[ModelBench] download ${preset.id}: $progress%');
            }
          }

          final provider = GemmaLlmProvider(service, preset);

          for (final benchmarkCase in cases) {
            final outputDir = Directory.systemTemp.createTempSync('gemma_kb_');
            addTearDown(() {
              if (outputDir.existsSync()) {
                outputDir.deleteSync(recursive: true);
              }
            });
            print('[ModelBench] ${preset.id} / ${benchmarkCase.name}: '
                'output=${outputDir.absolute.path}');

            final orchestrator = KBOrchestrator(provider);
            final buildResult = await orchestrator.run(
              KBOrchestratorParams(
                sourceName: '${preset.id}_${benchmarkCase.name}'
                    .replaceAll(RegExp(r'\s+'), '_'),
                inputText: benchmarkCase.transcript,
                outputPath: outputDir.path,
                processingMode: KBProcessingMode.processOnly,
                analysisTemplate: 'kb_analysis_compact.xml',
                analysisExtraInstructions:
                    'Extract all clear questions and answers. '
                    'Set the author field to the speaker name shown in the transcript. '
                    'Preserve the topic area and 1-3 specific topics for each record.',
              ),
            );

            expect(
              buildResult.success,
              isTrue,
              reason: '${preset.id} should build KB successfully',
            );
            expect(
              buildResult.questionsCount,
              greaterThanOrEqualTo(benchmarkCase.minQuestions),
              reason: '${preset.id} should extract at least '
                  '${benchmarkCase.minQuestions} questions',
            );
            expect(
              buildResult.answersCount,
              greaterThanOrEqualTo(benchmarkCase.minAnswers),
              reason: '${preset.id} should extract at least '
                  '${benchmarkCase.minAnswers} answers',
            );

            final engine = KBSearchEngine.file(outputDir, provider: provider);

            for (final expectation in benchmarkCase.searchQueries) {
              print('[ModelBench] ${preset.id} / ${benchmarkCase.name}: '
                  'search "${expectation.query}"');
              final result = await engine.searchByText(
                expectation.query,
                matchAll: false,
                maxGeneratedTags: 6,
              );

              print('[ModelBench]   tags=${result.generatedTags} '
                  'results=${result.results.length}');

              expect(
                result.generatedTags,
                isNotEmpty,
                reason: '${preset.id}: query "${expectation.query}" '
                    'should generate tags',
              );

              final lowerTags = result.generatedTags
                  .map((t) => t.toLowerCase())
                  .toSet();
              expect(
                expectation.expectedKeywordsInTags.any(
                  (keyword) => lowerTags.any(
                    (tag) => tag.contains(keyword) || keyword.contains(tag),
                  ),
                ),
                isTrue,
                reason: '${preset.id}: expected one of '
                    '${expectation.expectedKeywordsInTags} to overlap with '
                    'generated tags $lowerTags',
              );

              expect(
                result.results,
                isNotEmpty,
                reason: '${preset.id}: query "${expectation.query}" '
                    'should return records',
              );

              final titles = result.results
                  .map((r) => (r.title ?? '').toLowerCase())
                  .toList();
              expect(
                titles.any(
                  (title) => expectation.expectedResultKeywordsInTitle.any(
                    (keyword) =>
                        title.contains(keyword) || keyword.contains(title),
                  ),
                ),
                isTrue,
                reason: '${preset.id}: expected one of '
                    '${expectation.expectedResultKeywordsInTitle} to appear '
                    'in result titles $titles',
              );
            }
          }

          print('[ModelBench] ${preset.id}: ALL CASES PASSED');
        },
        // Qwen3-0.6B is CPU-only and tiny, so each inference is slow. Give it
        // extra wall-clock time to finish the analysis + searches.
        timeout: Timeout(
          Duration(seconds: preset.id == 'qwen3-0.6b' ? 2700 : 900),
        ),
      );
    }
  });
}

GemmaModelPreset _defaultOverride(GemmaModelPreset base) {
  return base.copyWith(
    maxOutputTokens: base.maxTokens ~/ 2,
    temperature: 0.0,
    preferredBackend: base.id == 'phi4-mini'
        ? PreferredBackend.cpu
        : base.preferredBackend,
  );
}
