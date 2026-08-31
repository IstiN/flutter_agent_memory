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
TYPE=Q | ID=q_1 | AUTHOR=Alice | DATE=2024-01-01T10:00:00Z | AREA=development | TOPICS=dart-testing | TAGS=dart;testing | ANSWERED_BY=a_1 | LINKS= | START=How do | END=test Dart code?
TYPE=A | ID=a_1 | AUTHOR=Bob | DATE=2024-01-01T10:05:00Z | AREA=development | TOPICS=dart-testing | TAGS=test-package | ANSWERS_QUESTION=q_1 | QUALITY=0.9 | LINKS= | START=Use the | END=test package.
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

    final qFiles = Directory('${tmpDir.path}/questions')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    final aFiles = Directory('${tmpDir.path}/answers')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(qFiles, hasLength(1));
    expect(qFiles.single, matches(r'^q_0001_[0-9a-f]{4}\.md$'));
    expect(aFiles, hasLength(1));
    expect(aFiles.single, matches(r'^a_0001_[0-9a-f]{4}\.md$'));
  });

  test('regenerateStructureFromExistingFiles counts topics correctly', () async {
    final orchestrator = KBOrchestrator(FakeLlmProvider({}));

    Directory('${tmpDir.path}/topics').createSync(recursive: true);
    File('${tmpDir.path}/topics/dart.md').writeAsStringSync('');
    File('${tmpDir.path}/topics/flutter.md').writeAsStringSync('');
    File('${tmpDir.path}/topics/flutter-desc.md').writeAsStringSync('');

    final result = await orchestrator.regenerateStructureFromExistingFiles(
      tmpDir.path,
      'chat',
    );

    expect(result.success, isTrue);
    expect(result.topicsCount, 2);
  });
}
