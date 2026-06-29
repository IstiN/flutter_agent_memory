import 'dart:io';

import 'package:flutter_agent_memory/src/models/analysis_result.dart';
import 'package:flutter_agent_memory/src/models/answer.dart';
import 'package:flutter_agent_memory/src/models/note.dart';
import 'package:flutter_agent_memory/src/models/person_contributions.dart';
import 'package:flutter_agent_memory/src/models/question.dart';
import 'package:flutter_agent_memory/src/storage/kb_structure_builder.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;
  late KBStructureBuilder builder;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('kb_test_');
    builder = KBStructureBuilder();
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('writes question, answer and note files', () {
    final analysis = AnalysisResult(
      questions: [
        Question(id: 'q_0001', author: 'Alice', text: 'Q?', date: '2024-01-01', area: 'dev', topics: ['dart-testing'], tags: [], answeredBy: 'a_0001', links: []),
      ],
      answers: [
        Answer(id: 'a_0001', author: 'Bob', text: 'A', date: '2024-01-01', area: 'dev', topics: ['dart-testing'], tags: [], answersQuestion: 'q_0001', quality: 0.9, links: []),
      ],
      notes: [
        Note(id: 'n_0001', text: 'N', area: 'dev', topics: ['dart-testing'], tags: [], author: 'Alice', date: '2024-01-01', answersQuestions: [], links: []),
      ],
    );

    builder.buildQuestionFile(analysis.questions.first, tmpDir, 'test_source', analysis);
    builder.buildAnswerFile(analysis.answers.first, tmpDir, 'test_source');
    builder.buildNoteFile(analysis.notes.first, tmpDir, 'test_source');

    expect(File('${tmpDir.path}/questions/q_0001.md').existsSync(), isTrue);
    expect(File('${tmpDir.path}/answers/a_0001.md').existsSync(), isTrue);
    expect(File('${tmpDir.path}/notes/n_0001.md').existsSync(), isTrue);

    final qContent = File('${tmpDir.path}/questions/q_0001.md').readAsStringSync();
    expect(qContent, contains('**Asked by:** [[Alice]]'));
    expect(qContent, contains('![[a_0001]]'));
  });

  test('builds area and topic files', () {
    final analysis = AnalysisResult(
      questions: [
        Question(id: 'q_0001', author: 'Alice', text: 'Q?', date: '2024-01-01', area: 'development', topics: ['dart-testing'], tags: [], answeredBy: '', links: []),
      ],
      answers: [],
      notes: [],
    );

    builder.buildAreaStructure(analysis, tmpDir, 'src');
    builder.buildTopicFiles(analysis, tmpDir, 'src');

    expect(File('${tmpDir.path}/areas/development/development.md').existsSync(), isTrue);
    expect(File('${tmpDir.path}/topics/dart-testing.md').existsSync(), isTrue);
  });

  test('builds person profile', () {
    final contributions = PersonContributions()
      ..questions.add(const ContributionItem(id: 'q_0001', topic: 'dart-testing', date: '2024-01-01'));

    builder.buildPersonProfile('Alice Smith', tmpDir, 'src', 1, 0, 0, contributions);

    final file = File('${tmpDir.path}/people/alice_smith/alice_smith.md');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('name: "Alice Smith"'));
    expect(content, contains('[[../../questions/q_0001|q_0001]]'));
  });
}
