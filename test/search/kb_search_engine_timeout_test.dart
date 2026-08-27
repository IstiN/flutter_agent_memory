import 'dart:async';
import 'dart:io';

import 'package:flutter_agent_memory/src/llm/llm_message.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/search/kb_search_engine.dart';
import 'package:test/test.dart';

/// Provider whose LLM calls never complete — models an unresponsive
/// endpoint that used to hang `searchByText` forever.
class _HangingProvider implements LlmProvider {
  @override
  String get defaultModel => 'fake-model';

  @override
  Future<String> chat(
    String prompt, {
    String? model,
    void Function()? onCancel,
  }) => Completer<String>().future;

  @override
  Future<String> chatMessages(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) => chat(messages.last.content);

  @override
  Stream<String> chatStream(
    String prompt, {
    String? model,
    void Function()? onCancel,
  }) async* {
    yield await chat(prompt, model: model, onCancel: onCancel);
  }

  @override
  Stream<String> chatMessagesStream(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) async* {
    yield await chatMessages(messages, model: model, onCancel: onCancel);
  }

  @override
  Future<void> cancel() async {}
}

/// Provider that answers tag generation but hangs on rerank calls
/// (a rerank prompt contains the candidate record ids).
class _HangingRerankProvider implements LlmProvider {
  @override
  String get defaultModel => 'fake-model';

  @override
  Future<String> chat(
    String prompt, {
    String? model,
    void Function()? onCancel,
  }) {
    if (prompt.contains('n_0001') && prompt.contains('n_0002')) {
      return Completer<String>().future; // rerank stage hangs
    }
    return Future.value('TAG=dart\nTAG=testing');
  }

  @override
  Future<String> chatMessages(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) => chat(messages.last.content);

  @override
  Stream<String> chatStream(
    String prompt, {
    String? model,
    void Function()? onCancel,
  }) async* {
    yield await chat(prompt, model: model, onCancel: onCancel);
  }

  @override
  Stream<String> chatMessagesStream(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) async* {
    yield await chatMessages(messages, model: model, onCancel: onCancel);
  }

  @override
  Future<void> cancel() async {}
}

/// Provider that never answers at all, even to keyword-only stages — used to
/// verify the timeout is bounded and reported.
class _SlowEverythingProvider extends _HangingProvider {}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('search_timeout_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  Future<void> seedKb() async {
    final notes = Directory('${tmpDir.path}/notes')
      ..createSync(recursive: true);
    File('${notes.path}/n_0001.md').writeAsStringSync('''
---
id: "n_0001"
type: "note"
author: "agent"
date: "2025-01-01"
area: "dev"
topics: ["dart"]
tags: ["dart", "isolate"]
---

# Note

Dart isolate basics explained in depth.
''');
    File('${notes.path}/n_0002.md').writeAsStringSync('''
---
id: "n_0002"
type: "note"
author: "agent"
date: "2025-01-02"
area: "dev"
topics: ["flutter"]
tags: ["flutter"]
---

# Note

Flutter widget rebuild rules and pitfalls.
''');
  }

  test(
    'searchByText returns keyword results when tag generation hangs',
    () async {
      await seedKb();
      final engine = KBSearchEngine.file(
        tmpDir,
        provider: _HangingProvider(),
        llmTimeout: const Duration(milliseconds: 120),
      );

      final result = await engine.searchByText('isolate basics dart');

      expect(result.generatedTags, isEmpty);
      expect(result.results.map((r) => r.id), contains('n_0001'));
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('Tag generation timed out'));
    },
  );

  test('searchByText keeps ranking when rerank hangs', () async {
    await seedKb();
    final engine = KBSearchEngine.file(
      tmpDir,
      provider: _HangingRerankProvider(),
      llmTimeout: const Duration(milliseconds: 120),
    );

    final result = await engine.searchByText('dart isolate rebuild testing');

    expect(result.generatedTags, contains('dart'));
    expect(result.results, isNotEmpty);
    expect(result.warnings.single, contains('Reranking timed out'));
  });

  test('searchByText completes within the configured timeout', () async {
    await seedKb();
    final engine = KBSearchEngine.file(
      tmpDir,
      provider: _SlowEverythingProvider(),
      llmTimeout: const Duration(milliseconds: 100),
    );

    final sw = Stopwatch()..start();
    await engine.searchByText('anything at all');
    sw.stop();

    // 2 stages × 100ms + generous CI margin; pre-fix this hung forever.
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('fast providers produce no warnings', () async {
    await seedKb();
    final engine = KBSearchEngine.file(
      tmpDir,
      provider: _HangingRerankProvider(),
      llmTimeout: const Duration(seconds: 5),
    );

    // rerankTopN: 0 disables the rerank stage entirely.
    final result = await engine.searchByText(
      'flutter widget rebuild',
      rerankTopN: 0,
    );

    expect(result.generatedTags, contains('dart'));
    expect(result.results.map((r) => r.id), contains('n_0002'));
    expect(result.warnings, isEmpty);
  });
}
