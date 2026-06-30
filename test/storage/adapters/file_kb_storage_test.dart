@TestOn('vm')
import 'dart:io';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:test/test.dart';

const _questionMarkdown = '''
---
id: "q_0001"
type: "question"
author: "Alice"
date: "2024-01-01"
area: "dev"
topics: ["dart"]
tags: ["dart", "testing"]
---

# Question

How to test?
''';

void main() {
  group('FileKbStorage', () {
    late Directory tmpDir;
    late FileKbStorage storage;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('file_kb_');
      storage = FileKbStorage(tmpDir);
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('writes and reads entity files', () {
      storage.writeEntity('question', 'q_0001', _questionMarkdown);

      final file = File('${tmpDir.path}/questions/q_0001.md');
      expect(file.existsSync(), isTrue);
      expect(storage.readEntity('question', 'q_0001'), _questionMarkdown);
    });

    test('lists entity ids and deletes entities', () {
      storage.writeEntity('question', 'q_0001', _questionMarkdown);
      storage.writeEntity(
        'question',
        'q_0002',
        _questionMarkdown.replaceAll('q_0001', 'q_0002'),
      );
      storage.writeEntity(
        'note',
        'n_0001',
        _questionMarkdown.replaceAll('q_0001', 'n_0001'),
      );

      expect(storage.listEntityIds('question'), ['q_0001', 'q_0002']);
      expect(storage.listEntityIds('note'), ['n_0001']);

      storage.deleteEntity('question', 'q_0001');
      expect(storage.listEntityIds('question'), ['q_0002']);
    });

    test('reads and writes structure files', () {
      storage.writeFile('INDEX.md', '# Index');
      storage.writeFile('stats/activity_timeline.md', '- today');

      expect(storage.readFile('INDEX.md'), '# Index');
      expect(storage.readFile('missing.md'), isNull);
      expect(storage.listFilePaths('stats/'), ['stats/activity_timeline.md']);
    });

    test('initialize creates directories and clean removes content', () {
      storage.initialize();
      expect(Directory('${tmpDir.path}/questions').existsSync(), isTrue);
      expect(Directory('${tmpDir.path}/notes').existsSync(), isTrue);

      storage.writeEntity('question', 'q_0001', _questionMarkdown);
      storage.initialize(clean: true);
      expect(storage.readEntity('question', 'q_0001'), isNull);
    });

    test('loadContext scans files and computes next ids', () {
      storage.writeEntity('question', 'q_0001', _questionMarkdown);
      storage.writeEntity(
        'answer',
        'a_0001',
        _questionMarkdown
            .replaceAll('q_0001', 'a_0001')
            .replaceAll('type: "question"', 'type: "answer"')
            .replaceAll('Question', 'Answer'),
      );

      final context = storage.loadContext();
      expect(context.existingPeople, {'Alice'});
      expect(context.existingTopics, {'dart'});
      expect(context.maxQuestionId, 1);
      expect(context.maxAnswerId, 1);
      expect(context.nextQuestionId(), 2);
    });

    test('describeLocation returns the entity file path', () {
      expect(
        storage.describeLocation('question', 'q_0001'),
        '${tmpDir.path}/questions/q_0001.md',
      );
    });
  });
}
