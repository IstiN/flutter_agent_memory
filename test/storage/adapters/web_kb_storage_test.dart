import 'package:flutter_agent_memory/src/storage/web/web_kb_storage.dart';
import 'package:flutter_agent_memory/src/storage/web/web_storage_backend.dart';
import 'package:test/test.dart';

class _FakeBackend implements WebStorageBackend {
  final Map<String, String> _data = {};

  @override
  String? getItem(String key) => _data[key];

  @override
  void setItem(String key, String value) => _data[key] = value;

  @override
  void removeItem(String key) => _data.remove(key);

  @override
  List<String> keys() => _data.keys.toList();

  @override
  void clear() => _data.clear();
}

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
  group('WebKbStorage', () {
    late _FakeBackend backend;
    late WebKbStorage storage;

    setUp(() {
      backend = _FakeBackend();
      storage = WebKbStorage(backend: backend);
    });

    test('reads, writes, lists and deletes entities', () {
      expect(storage.readEntity('question', 'q_0001'), isNull);

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

    test('loadContext scans records and computes next ids', () async {
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
      expect(context.maxQuestionId, 1);
      expect(context.maxAnswerId, 1);
      expect(context.maxNoteId, 0);
      expect(context.nextQuestionId(), 2);
    });

    test('does not touch unrelated backend keys when cleaning', () {
      backend.setItem('other-app:setting', 'keep');
      storage.writeEntity('question', 'q_0001', _questionMarkdown);

      storage.initialize(clean: true);
      expect(backend.getItem('other-app:setting'), 'keep');
      expect(storage.readEntity('question', 'q_0001'), isNull);
    });

    test('describeLocation returns a web URI', () {
      expect(
        storage.describeLocation('question', 'q_0001'),
        'web://question/q_0001',
      );
    });
  });
}
