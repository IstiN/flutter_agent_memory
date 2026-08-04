import 'dart:io';

import 'package:flutter_agent_memory/src/llm/llm_message.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/models/memory_level.dart';
import 'package:flutter_agent_memory/src/models/relation.dart';
import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:test/test.dart';

class _TagProvider implements LlmProvider {
  @override
  String get defaultModel => 'fake';

  @override
  Future<String> chat(String prompt, {String? model, void Function()? onCancel}) async {
    return 'TAG=dart\nTAG=testing';
  }

  @override
  Future<String> chatMessages(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) async => chat(messages.last.content);

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

class _ConsolidationProvider implements LlmProvider {
  @override
  String get defaultModel => 'fake';

  @override
  Future<String> chat(String prompt, {String? model, void Function()? onCancel}) async {
    return 'SUMMARY=Consolidated summary.\n'
        'SKILL | ID=sk_1 | TITLE=Test skill | INSTRUCTION=Run tests. | TAGS=dart,testing';
  }

  @override
  Future<String> chatMessages(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) async => chat(messages.last.content);

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

void main() {
  late Directory tmpDir;
  late KBMemoryStore store;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('memory_store_');
    store = KBMemoryStore.file(tmpDir, source: 'agent');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('enrich falls back to generated tags when area/tags missing', () async {
    final enrichedStore = KBMemoryStore.file(
      tmpDir,
      source: 'agent',
      provider: _TagProvider(),
    );

    final record = await enrichedStore.addQuestion(text: 'How to test Dart?');
    expect(record.question!.area, 'development');
    expect(record.question!.topics, ['dart']);
    expect(record.question!.tags, contains('dart'));
  });

  test('enrich keeps explicit area and tags', () async {
    final record = await store.addQuestion(
      text: 'How to test?',
      area: 'custom',
      tags: ['x'],
    );
    expect(record.question!.area, 'custom');
    expect(record.question!.tags, contains('x'));
  });

  test('enrich uses general area without provider', () async {
    final record = await store.addQuestion(text: 'How to test?');
    expect(record.question!.area, 'general');
  });

  test('adds a question and assigns sequential id', () async {
    final record = await store.addQuestion(
      text: 'How to test?',
      area: 'development',
      tags: ['dart', 'testing'],
    );
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

  test('recordAccess increments counter and sets lastAccessedAt for question',
      () async {
    final record = await store.addQuestion(
      text: 'Q?',
      area: 'dev',
      tags: ['x'],
    );
    await store.recordAccess(record.id);

    final updated = await store.findById(record.id);
    expect(updated, isNotNull);
    expect(updated!.accessCount, 1);
    expect(updated.lastAccessedAt, isNotNull);
  });

  test('recordAccess works for answers and notes', () async {
    final answer = await store.addAnswer(
      text: 'A.',
      area: 'dev',
      tags: ['y'],
    );
    final note = await store.addNote(
      text: 'N.',
      area: 'dev',
      tags: ['z'],
    );

    await store.recordAccess(answer.id);
    await store.recordAccess(note.id);

    expect((await store.findById(answer.id))!.accessCount, 1);
    expect((await store.findById(note.id))!.accessCount, 1);
  });

  test('recordAccess ignores unknown id', () async {
    await store.recordAccess('q_unknown');
    expect(await store.findById('q_unknown'), isNull);
  });

  test('deleteRecord removes file', () async {
    final record = await store.addQuestion(
      text: 'Q?',
      area: 'dev',
      tags: ['x'],
    );
    await store.deleteRecord(record.id);
    expect(
      File('${tmpDir.path}/questions/${record.id}.md').existsSync(),
      isFalse,
    );
    expect(await store.findById(record.id), isNull);
  });

  test('list returns records sorted by lastAccessed', () async {
    await store.addQuestion(text: 'Q1', area: 'dev', tags: ['x']);
    await store.addAnswer(text: 'A1', area: 'dev', tags: ['y']);

    final records = await store.list();
    expect(records.length, 2);
    expect(records.first.entityType, 'answer'); // last created has later date
  });

  test('rank lists records by accessCount', () async {
    final q = await store.addQuestion(text: 'Q?', area: 'dev', tags: ['x']);
    await store.addAnswer(text: 'A?', area: 'dev', tags: ['y']);
    await store.recordAccess(q.id);
    await store.recordAccess(q.id);

    final ranked = await store.list(sortBy: 'accessCount');
    expect(ranked.first.id, q.id);
    expect(ranked.first.accessCount, 2);
  });

  test(
    'updateRecord modifies text and tags without duplicating system tags',
    () async {
      final record = await store.addQuestion(
        text: 'Original',
        area: 'dev',
        tags: ['old'],
      );
      final updated = await store.updateRecord(
        record.id,
        text: 'Updated',
        tags: ['new'],
      );

      expect(updated.title, 'Updated');
      expect(updated.tags, contains('#question'));
      expect(updated.tags, contains('#source_agent'));
      expect(updated.tags, contains('new'));
      expect(updated.tags.where((t) => t == '#question').length, 1);
    },
  );

  test('updateRecord updates a note with metadata', () async {
    final record = await store.addNote(
      text: 'Original note.',
      area: 'dev',
      tags: ['old'],
    );
    final updated = await store.updateRecord(
      record.id,
      text: 'Updated note.',
      tags: ['new'],
      importance: 0.9,
      memoryType: 'fact',
      level: MemoryLevel.consolidated,
      relations: const [
        Relation(
          source: 'placeholder',
          target: 'n_0002',
          type: RelationType.supports,
        ),
      ],
    );

    expect(updated.title, 'Updated note.');
    expect(updated.note!.tags, contains('new'));
    expect(updated.note!.memoryType, 'fact');
    expect(updated.note!.level, MemoryLevel.consolidated);
    expect(updated.note!.relations, hasLength(1));
  });

  test('addNote persists memory level and relations', () async {
    final record = await store.addNote(
      text: 'Consolidated insight.',
      area: 'dev',
      tags: ['x'],
      level: MemoryLevel.consolidated,
      relations: const [
        Relation(
          source: 'placeholder',
          target: 'n_0002',
          type: RelationType.supports,
        ),
      ],
    );

    final file = File(record.path);
    final content = file.readAsStringSync();

    expect(content, contains('level: 2'));
    expect(content, contains('relations: ["supports|n_0002"]'));
  });

  test('promote raises note memory level', () async {
    final record = await store.addNote(
      text: 'Raw idea.',
      area: 'dev',
      tags: ['x'],
    );
    expect(record.note!.level, MemoryLevel.raw);

    final promoted = await store.promote(record.id, MemoryLevel.concept);
    expect(promoted.note!.level, MemoryLevel.concept);

    final file = File(promoted.path);
    expect(file.readAsStringSync(), contains('level: 3'));
  });

  test('addRelation appends typed relation to note frontmatter', () async {
    final source = await store.addNote(
      text: 'Source.',
      area: 'dev',
      tags: ['x'],
    );
    final target = await store.addNote(
      text: 'Target.',
      area: 'dev',
      tags: ['y'],
    );

    await store.addRelation(
      source.id,
      target.id,
      RelationType.supports,
      weight: 1.5,
    );

    final updated = await store.findById(source.id);
    expect(updated, isNotNull);
    expect(updated!.note!.relations, hasLength(1));
    expect(updated.note!.relations.first.type, RelationType.supports);
    expect(updated.note!.relations.first.target, target.id);
    expect(updated.note!.relations.first.weight, 1.5);

    final content = File(updated.path).readAsStringSync();
    expect(content, contains('supports|${target.id}|1.50'));
  });

  test('addRelation is idempotent for duplicate relations', () async {
    final source = await store.addNote(
      text: 'Source.',
      area: 'dev',
      tags: ['x'],
    );
    final target = await store.addNote(
      text: 'Target.',
      area: 'dev',
      tags: ['y'],
    );

    await store.addRelation(source.id, target.id, RelationType.supports);
    await store.addRelation(source.id, target.id, RelationType.supports);

    final updated = await store.findById(source.id);
    expect(updated!.note!.relations, hasLength(1));
  });

  test('consolidate writes MEMORY.md and skill files', () async {
    final consolidatedStore = KBMemoryStore.file(
      tmpDir,
      source: 'agent',
      provider: _ConsolidationProvider(),
    );
    await consolidatedStore.addQuestion(text: 'Q?', area: 'dev', tags: ['x']);

    final result = await consolidatedStore.consolidate();
    expect(result.summary, 'Consolidated summary.');
    expect(result.skills, hasLength(1));

    final memoryFile = File('${tmpDir.path}/MEMORY.md');
    expect(memoryFile.existsSync(), isTrue);
    expect(memoryFile.readAsStringSync(), contains('Consolidated summary.'));

    final skillFile = File('${tmpDir.path}/skills/sk_0001.md');
    expect(skillFile.existsSync(), isTrue);
    expect(skillFile.readAsStringSync(), contains('Run tests.'));
  });
}
