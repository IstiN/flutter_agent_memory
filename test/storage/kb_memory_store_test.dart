import 'dart:io';

import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;
  late KBMemoryStore store;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('memory_store_');
    store = KBMemoryStore(tmpDir, source: 'agent');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('adds a question and assigns sequential id', () async {
    final record = await store.addQuestion(text: 'How to test?', area: 'development', tags: ['dart', 'testing']);
    expect(record.entityType, 'question');
    expect(record.id, 'q_0001');
    expect(File('${tmpDir.path}/questions/q_0001.md').existsSync(), isTrue);
  });

  test('adds an answer and a note', () async {
    final answer = await store.addAnswer(
      text: 'Use the test package.',
      area: 'development',
      tags: ['dart'],
      answersQuestion: 'q_0001',
    );
    final note = await store.addNote(
      text: 'Remember to run analyze.',
      area: 'development',
      tags: ['workflow'],
    );

    expect(answer.id, 'a_0001');
    expect(note.id, 'n_0001');
  });

  test('recordAccess increments counter and sets lastAccessedAt', () async {
    final record = await store.addQuestion(text: 'Q?', area: 'dev', tags: ['x']);
    store.recordAccess(record.id);

    final updated = store.findById(record.id);
    expect(updated, isNotNull);
    expect(updated!.accessCount, 1);
    expect(updated.lastAccessedAt, isNotNull);
  });

  test('deleteRecord removes file', () async {
    final record = await store.addQuestion(text: 'Q?', area: 'dev', tags: ['x']);
    store.deleteRecord(record.id);
    expect(File('${tmpDir.path}/questions/${record.id}.md').existsSync(), isFalse);
    expect(store.findById(record.id), isNull);
  });

  test('list returns records sorted by lastAccessed', () async {
    await store.addQuestion(text: 'Q1', area: 'dev', tags: ['x']);
    await store.addAnswer(text: 'A1', area: 'dev', tags: ['y']);

    final records = store.list();
    expect(records.length, 2);
    expect(records.first.entityType, 'answer'); // last created has later date
  });

  test('rank lists records by accessCount', () async {
    final q = await store.addQuestion(text: 'Q?', area: 'dev', tags: ['x']);
    await store.addAnswer(text: 'A?', area: 'dev', tags: ['y']);
    store.recordAccess(q.id);
    store.recordAccess(q.id);

    final ranked = store.list(sortBy: 'accessCount');
    expect(ranked.first.id, q.id);
    expect(ranked.first.accessCount, 2);
  });

  test('updateRecord modifies text and tags without duplicating system tags', () async {
    final record = await store.addQuestion(text: 'Original', area: 'dev', tags: ['old']);
    final updated = await store.updateRecord(record.id, text: 'Updated', tags: ['new']);

    expect(updated.title, 'Updated');
    expect(updated.tags, contains('#question'));
    expect(updated.tags, contains('#source_agent'));
    expect(updated.tags, contains('new'));
    expect(updated.tags.where((t) => t == '#question').length, 1);
  });
}
