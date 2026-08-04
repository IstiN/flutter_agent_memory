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
        Question(
          id: 'q_0001',
          author: 'Alice',
          text: 'Q?',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart-testing'],
          tags: [],
          answeredBy: 'a_0001',
          links: [],
        ),
      ],
      answers: [
        Answer(
          id: 'a_0001',
          author: 'Bob',
          text: 'A',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart-testing'],
          tags: [],
          answersQuestion: 'q_0001',
          quality: 0.9,
          links: [],
        ),
      ],
      notes: [
        Note(
          id: 'n_0001',
          text: 'N',
          area: 'dev',
          topics: ['dart-testing'],
          tags: [],
          author: 'Alice',
          date: '2024-01-01',
          answersQuestions: [],
          links: [],
        ),
      ],
    );

    builder.buildQuestionFile(
      analysis.questions.first,
      tmpDir,
      'test_source',
      analysis,
    );
    builder.buildAnswerFile(analysis.answers.first, tmpDir, 'test_source');
    builder.buildNoteFile(analysis.notes.first, tmpDir, 'test_source');

    expect(File('${tmpDir.path}/questions/q_0001.md').existsSync(), isTrue);
    expect(File('${tmpDir.path}/answers/a_0001.md').existsSync(), isTrue);
    expect(File('${tmpDir.path}/notes/n_0001.md').existsSync(), isTrue);

    final qContent = File(
      '${tmpDir.path}/questions/q_0001.md',
    ).readAsStringSync();
    expect(qContent, contains('**Asked by:** [[Alice]]'));
    expect(qContent, contains('![[a_0001]]'));
  });

  test('builds area and topic files', () {
    final analysis = AnalysisResult(
      questions: [
        Question(
          id: 'q_0001',
          author: 'Alice',
          text: 'Q?',
          date: '2024-01-01',
          area: 'development',
          topics: ['dart-testing'],
          tags: [],
          answeredBy: '',
          links: [],
        ),
      ],
      answers: [],
      notes: [],
    );

    builder.buildAreaStructure(analysis, tmpDir, 'src');
    builder.buildTopicFiles(analysis, tmpDir, 'src');

    expect(
      File('${tmpDir.path}/areas/development/development.md').existsSync(),
      isTrue,
    );
    expect(File('${tmpDir.path}/topics/dart-testing.md').existsSync(), isTrue);
  });

  test('updateTopicWithStats injects activity and contributors', () {
    final topicDir = Directory('${tmpDir.path}/topics/dart')..createSync(recursive: true);
    File('${topicDir.path}/dart.md').writeAsStringSync('''---
type: topic
title: Dart
id: dart
sources: []
contributors: []
created: 2024-01-01T00:00:00Z
---

# Dart

![[dart-desc]]

<!-- AUTO_GENERATED_START -->
*placeholder*
<!-- AUTO_GENERATED_END -->
''');

    builder.updateTopicWithStats(tmpDir, 'dart', 3, 2, 1, ['Bob', 'Alice']);

    final content = File('${topicDir.path}/dart.md').readAsStringSync();
    expect(content, contains('Questions: 3'));
    expect(content, contains('Answers: 2'));
    expect(content, contains('Notes: 1'));
    expect(content, contains('[[Alice|Alice]]'));
    expect(content, contains('[[Bob|Bob]]'));
  });

  test('updateTopicWithStats skips missing topic file', () {
    expect(() => builder.updateTopicWithStats(tmpDir, 'missing', 1, 0, 0, []),
        returnsNormally);
  });

  test('buildTopicFiles links questions, answers and notes', () {
    final analysis = AnalysisResult(
      questions: [
        Question(
          id: 'q_1',
          author: 'Alice',
          text: 'Q1?',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart'],
          tags: [],
          answeredBy: 'a_1',
          links: [],
        ),
        Question(
          id: 'q_2',
          author: 'Alice',
          text: 'Q2?',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart'],
          tags: [],
          answeredBy: '',
          links: [],
        ),
      ],
      answers: [
        Answer(
          id: 'a_1',
          author: 'Bob',
          text: 'A1',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart'],
          tags: [],
          answersQuestion: 'q_1',
          quality: 1.0,
          links: [],
        ),
        Answer(
          id: 'a_2',
          author: 'Bob',
          text: 'Standalone answer',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart'],
          tags: [],
          answersQuestion: '',
          quality: 1.0,
          links: [],
        ),
      ],
      notes: [
        Note(
          id: 'n_1',
          author: 'Carol',
          text: 'Note answering q_2',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart'],
          tags: [],
          answersQuestions: ['q_2'],
          links: [],
        ),
        Note(
          id: 'n_2',
          author: 'Carol',
          text: 'Standalone note',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart'],
          tags: [],
          answersQuestions: [],
          links: [],
        ),
      ],
    );

    builder.buildTopicFiles(analysis, tmpDir, 'src');

    final content = File('${tmpDir.path}/topics/dart.md').readAsStringSync();
    expect(content, contains('## Questions with Answers'));
    expect(content, contains('![[q_1]]'));
    expect(content, contains('![[q_2]]'));
    expect(content, isNot(contains('## Unanswered Questions')));
    expect(content, contains('## Notes'));
    expect(content, contains('![[n_2]]'));
    expect(content, contains('## Additional Answers'));
    expect(content, contains('![[a_2]]'));
    expect(content, isNot(contains('![[a_1]]')));
    expect(content, isNot(contains('![[n_1]]')));
  });

  test('excludes answers linked only via answeredBy', () {
    final analysis = AnalysisResult(
      questions: [
        Question(
          id: 'q_1',
          author: 'Alice',
          text: 'Q1?',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart'],
          tags: [],
          answeredBy: 'a_3',
          links: [],
        ),
      ],
      answers: [
        Answer(
          id: 'a_3',
          author: 'Bob',
          text: 'Linked by answeredBy',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart'],
          tags: [],
          answersQuestion: '',
          quality: 1.0,
          links: [],
        ),
        Answer(
          id: 'a_4',
          author: 'Bob',
          text: 'Standalone answer',
          date: '2024-01-01',
          area: 'dev',
          topics: ['dart'],
          tags: [],
          answersQuestion: '',
          quality: 1.0,
          links: [],
        ),
      ],
      notes: [],
    );

    builder.buildTopicFiles(analysis, tmpDir, 'src');

    final content = File('${tmpDir.path}/topics/dart.md').readAsStringSync();
    expect(content, contains('## Questions with Answers'));
    expect(content, contains('![[q_1]]'));
    expect(content, contains('![[a_3]]'));
    expect(content, contains('## Additional Answers'));
    expect(content, contains('![[a_4]]'));
  });

  test('builds person profile', () {
    final contributions = PersonContributions()
      ..questions.add(
        const ContributionItem(
          id: 'q_0001',
          topic: 'dart-testing',
          date: '2024-01-01',
        ),
      );

    builder.buildPersonProfile(
      'Alice Smith',
      tmpDir,
      'src',
      1,
      0,
      0,
      contributions,
    );

    final file = File('${tmpDir.path}/people/alice_smith/alice_smith.md');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('name: "Alice Smith"'));
    expect(content, contains('[[../../questions/q_0001|q_0001]]'));
  });

  test('updates existing person profile', () {
    final personDir = Directory('${tmpDir.path}/people/alice_smith')
      ..createSync(recursive: true);
    File('${personDir.path}/alice_smith.md').writeAsStringSync('''---
name: "Alice Smith"
type: person
sources: [src]
questionsAsked: 1
answersProvided: 0
notesContributed: 0
---
# Alice Smith

<!-- AUTO_GENERATED_START -->
Old content
<!-- AUTO_GENERATED_END -->
''');

    final contributions = PersonContributions()
      ..answers.add(
        const ContributionItem(
          id: 'a_0001',
          topic: 'dart-testing',
          date: '2024-01-02',
        ),
      );

    builder.buildPersonProfile(
      'Alice Smith',
      tmpDir,
      'src',
      1,
      1,
      0,
      contributions,
    );

    final content = File('${personDir.path}/alice_smith.md')
        .readAsStringSync();
    expect(content, contains('questionsAsked: 1'));
    expect(content, contains('answersProvided: 1'));
    expect(content, contains('[[../../answers/a_0001|a_0001]]'));
    expect(content, isNot(contains('Old content')));
  });
}
