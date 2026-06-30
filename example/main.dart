import 'dart:io';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';

/// Minimal example: build a small knowledge base from a text file and search it.
Future<void> main(List<String> args) async {
  const outputPath = 'example_kb';
  final outputDir = Directory(outputPath);

  // 1. Create an LLM provider from environment variables.
  final config = LlmConfig.fromEnvironment(provider: 'openai');
  if (!config.isConfigured) {
    stderr.writeln('Set OPENAI_API_KEY and OPENAI_MODEL to run this example.');
    exit(1);
  }
  final provider = ProviderFactory.create(config);

  // 2. Process an input file (or pass raw text).
  final inputText =
      '''
Dart is a client-optimized language for fast apps on any platform.
How do I handle async errors in Dart?
Use try/catch or Result/AsyncError wrappers.
'''
          .trim();

  final orchestrator = KBOrchestrator(provider);
  final result = await orchestrator.run(
    KBOrchestratorParams(
      sourceName: 'example',
      inputText: inputText,
      outputPath: outputPath,
    ),
  );

  stdout.writeln('Processing result: ${result.success} – ${result.message}');

  // 3. Search the generated knowledge base.
  final engine = KBSearchEngine.file(outputDir, provider: provider);
  final searchResult = await engine.searchByText(
    'async errors in Dart',
    matchAll: false,
  );

  stdout.writeln('Generated tags: ${searchResult.generatedTags}');
  for (final r in searchResult.results) {
    stdout.writeln('- ${r.id}: ${r.title}');
  }
}
