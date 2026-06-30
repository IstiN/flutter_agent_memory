import 'dart:io';

import 'package:flutter_agent_memory/src/core/kb_orchestrator.dart';
import 'package:flutter_agent_memory/src/core/kb_orchestrator_params.dart';
import 'package:test/test.dart';

import '../fake_llm_provider.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('orch_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('runs full pipeline with fake provider', () async {
    final fakeResponse = '''
{
  "questions": [
    {
      "id": "q_1",
      "author": "Alice",
      "text": "How do I test Dart code?",
      "date": "2024-01-01T10:00:00Z",
      "area": "development",
      "topics": ["dart-testing"],
      "tags": ["dart", "testing"],
      "answeredBy": "",
      "links": []
    }
  ],
  "answers": [
    {
      "id": "a_1",
      "author": "Bob",
      "text": "Use the test package.",
      "date": "2024-01-01T10:05:00Z",
      "area": "development",
      "topics": ["dart-testing"],
      "tags": ["test-package"],
      "answersQuestion": "q_1",
      "quality": 0.9,
      "links": []
    }
  ],
  "notes": []
}
''';

    final provider = FakeLlmProvider({'Analyze': fakeResponse});
    final orchestrator = KBOrchestrator(provider);
    final result = await orchestrator.run(
      KBOrchestratorParams(
        sourceName: 'chat',
        inputText:
            'Alice: How do I test Dart code?\nBob: Use the test package.',
        outputPath: tmpDir.path,
      ),
    );

    expect(result.success, isTrue);
    expect(result.questionsCount, 1);
    expect(result.answersCount, 1);
    expect(result.peopleCount, 2);

    final qFile = File('${tmpDir.path}/questions/q_0001.md');
    final aFile = File('${tmpDir.path}/answers/a_0001.md');
    expect(qFile.existsSync(), isTrue);
    expect(aFile.existsSync(), isTrue);
  });
}
