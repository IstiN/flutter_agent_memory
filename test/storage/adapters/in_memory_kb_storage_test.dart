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
  group('InMemoryKbStorage', () {
    late InMemoryKbStorage storage;

    setUp(() {
      storage = InMemoryKbStorage();
    });

    test('reads, writes, lists and deletes entities', () {
      expect(storage.readEntity('question', 'q_0001'), isNull);
      expect(storage.listEntityIds('question'), isEmpty);

      storage.writeEntity('question', 'q_0001', _questionMarkdown);
      expect(storage.readEntity('question', 'q_0001'), _questionMarkdown);
      expect(storage.listEntityIds('question'), ['q_0001']);

      storage.writeEntity(
        'question',
        'q_0002',
        _questionMarkdown.replaceAll('q_0001', 'q_0002'),
      );
      expect(storage.listEntityIds('question'), ['q_0001', 'q_0002']);

      storage.deleteEntity('question', 'q_0001');
      expect(storage.readEntity('question', 'q_0001'), isNull);
      expect(storage.listEntityIds('question'), ['q_0002']);
    });

    test('reads, writes, lists and cleans files', () {
      storage.writeFile('INDEX.md', '# Index');
      storage.writeFile('stats/activity_timeline.md', '- today');

      expect(storage.readFile('INDEX.md'), '# Index');
      expect(storage.readFile('missing.md'), isNull);
      expect(storage.listFilePaths('stats/'), ['stats/activity_timeline.md']);

      storage.initialize(clean: true);
      expect(storage.readFile('INDEX.md'), isNull);
      expect(storage.listFilePaths('stats/'), isEmpty);
    });

    test('loadContext scans existing records and computes next ids', () async {
      storage.writeEntity('question', 'q_0001', _questionMarkdown);
      storage.writeEntity(
        'answer',
        'a_0001',
        _questionMarkdown
            .replaceAll('q_0001', 'a_0001')
            .replaceAll('type: "question"', 'type: "answer"')
            .replaceAll('Question', 'Answer'),
      );

      final context = await storage.loadContext();
      expect(context.existingPeople, {'Alice'});
      expect(context.existingTopics, {'dart'});
      expect(context.existingQuestions, hasLength(1));
      expect(context.maxQuestionId, 1);
      expect(context.maxAnswerId, 1);
      expect(context.maxNoteId, 0);
      expect(context.nextQuestionId(), 2);
    });

    test('describeLocation returns a memory URI', () {
      expect(
        storage.describeLocation('question', 'q_0001'),
        'memory://question/q_0001',
      );
    });
  });
}
