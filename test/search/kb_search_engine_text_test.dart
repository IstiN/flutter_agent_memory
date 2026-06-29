import 'dart:io';

import 'package:flutter_agent_memory/src/llm/llm_message.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/search/kb_search_engine.dart';
import 'package:test/test.dart';

class _FakeTagProvider implements LlmProvider {
  @override
  String get defaultModel => 'fake';

  @override
  Future<String> chat(String prompt, {String? model}) async {
    return '{"tags": ["unit-tests", "dart"]}';
  }

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) async =>
      chat(messages.first.content);
}

void main() {
  late Directory tmpDir;
  late KBSearchEngine engine;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('kb_text_search_');
    engine = KBSearchEngine(tmpDir, provider: _FakeTagProvider());

    Directory('${tmpDir.path}/questions').createSync(recursive: true);
    Directory('${tmpDir.path}/answers').createSync(recursive: true);

    File('${tmpDir.path}/questions/q_0001.md').writeAsStringSync('''
---
id: "q_0001"
type: "question"
author: "Alice"
date: "2024-01-01"
area: "dev"
topics: ["dart"]
tags: ["unit-tests", "dart"]
---

# Question

How to test?
''');

    File('${tmpDir.path}/answers/a_0001.md').writeAsStringSync('''
---
id: "a_0001"
type: "answer"
author: "Bob"
date: "2024-01-01"
area: "dev"
topics: ["dart"]
tags: ["test-package", "dart"]
quality: 0.9
---

# Answer

Use the test package.
''');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('searchByText generates tags and returns matching records', () async {
    final result = await engine.searchByText('How do I write unit tests in Dart?');
    expect(result.generatedTags, containsAll(['unit-tests', 'dart']));
    expect(result.results.length, greaterThanOrEqualTo(1));
    expect(result.results.map((r) => r.id).toSet(), contains('q_0001'));
  });

  test('searchByText returns empty result when no tags match', () async {
    final engine2 = KBSearchEngine(tmpDir, provider: _AlwaysUnknownTagsProvider());
    final result = await engine2.searchByText('kubernetes deployments');
    expect(result.results, isEmpty);
  });

  test('searchByText throws when provider is missing', () async {
    final engineWithoutProvider = KBSearchEngine(tmpDir);
    expect(() => engineWithoutProvider.searchByText('dart tests'), throwsStateError);
  });
}

class _AlwaysUnknownTagsProvider implements LlmProvider {
  @override
  String get defaultModel => 'fake';

  @override
  Future<String> chat(String prompt, {String? model}) async => '{"tags": ["kubernetes"]}';

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) async =>
      chat(messages.first.content);
}
