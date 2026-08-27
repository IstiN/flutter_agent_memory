import 'dart:io';

import 'package:flutter_agent_memory/src/llm/llm_message.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/storage/in_memory_kb_storage.dart';
import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:flutter_agent_memory/src/storage/sqlite_kb_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// LLM provider that records prompts and answers with a fixed summary.
class _RecordingProvider implements LlmProvider {
  final List<String> prompts = [];

  @override
  String get defaultModel => 'fake-model';

  @override
  Future<String> chat(
    String prompt, {
    String? model,
    void Function()? onCancel,
  }) async {
    prompts.add(prompt);
    return 'SUMMARY=Consolidated summary.\n';
  }

  @override
  Future<String> chatMessages(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) => chat(messages.last.content, model: model, onCancel: onCancel);

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
  group('delete by id', () {
    late Directory tmpDir;
    late KBMemoryStore store;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('memory_delete_');
      store = KBMemoryStore.file(tmpDir, source: 'agent');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('removes the record and is idempotent', () async {
      final record = await store.addNote(
        text: 'Deploy happens on Fridays.',
        area: 'dev',
        tags: ['x'],
      );

      expect(await store.deleteRecord(record.id), isTrue);
      expect(
        File('${tmpDir.path}/notes/${record.id}.md').existsSync(),
        isFalse,
      );
      expect(await store.findById(record.id), isNull);
      expect(await store.deleteRecord(record.id), isFalse);
    });

    test('records a tombstone in the deletion ledger', () async {
      final record = await store.addNote(text: 'Tombstoned fact.');
      await store.deleteRecord(record.id);

      expect(await store.storage.readFile('DELETIONS.md'), contains(record.id));
      expect(await store.isDeleted(record.id), isTrue);
      expect(await store.hasDeletedText('Tombstoned fact.'), isTrue);
    });

    test('bumps the revision so stale consolidation writes fail', () async {
      await store.storage.writeFile('MEMORY.md', 'summary v1');
      final revisionBefore = await store.readMemoryRevision();
      final record = await store.addNote(text: 'Doomed note.');

      await store.deleteRecord(record.id);

      final ok = await store.writeMemoryRevision(
        'summary v2',
        revisionBefore.hash,
      );
      expect(ok, isFalse);

      // After the delete the current hash differs from the pre-delete hash
      // even though MEMORY.md itself was not touched.
      final revisionAfter = await store.readMemoryRevision();
      expect(revisionAfter.hash, isNot(revisionBefore.hash));
    });

    test('rebuilds GRAPH.md without the deleted node', () async {
      final kept = await store.addNote(text: 'Kept note.', area: 'dev');
      final removed = await store.addNote(text: 'Removed note.', area: 'dev');
      await store.buildGraph();
      expect(await store.storage.readFile('GRAPH.md'), contains(removed.id));

      await store.deleteRecord(removed.id);

      final graph = await store.storage.readFile('GRAPH.md');
      expect(graph, isNotNull);
      expect(graph, contains(kept.id));
      expect(graph, isNot(contains(removed.id)));
    });

    test('ignores unknown id prefixes', () async {
      expect(await store.deleteRecord('x_0001'), isFalse);
      expect(await store.isDeleted('x_0001'), isFalse);
    });

    test('maintain() expiry goes through the deletion ledger', () async {
      final expiringStore = KBMemoryStore.file(
        tmpDir,
        source: 'agent',
        promotionPolicy: const MemoryPromotionPolicy(
          rawToConsolidatedAfter: Duration(days: 365),
          rawExpiryAfter: Duration(seconds: 0),
          consolidatedToConceptAfter: Duration(days: 365),
        ),
      );
      final note = await expiringStore.addNote(text: 'Expired raw note.');
      await expiringStore.maintainMemoryLevels();

      expect(await expiringStore.findById(note.id), isNull);
      expect(await expiringStore.isDeleted(note.id), isTrue);
    });
  });

  group('delete by text', () {
    late Directory tmpDir;
    late KBMemoryStore store;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('memory_delete_text_');
      store = KBMemoryStore.file(tmpDir, source: 'agent');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('matches normalized text across types', () async {
      final note = await store.addNote(text: 'Release is frozen on Friday.');
      await store.addQuestion(
        text: 'Release is frozen on Friday.',
        area: 'dev',
      );

      final result = await store.deleteRecordByText(
        '  release   is FROZEN on friday. ',
      );

      expect(result.deleted, isTrue);
      expect(result.deletedIds, containsAll([note.id]));
      expect(await store.findById(note.id), isNull);
      // The question with the same text is removed too.
      expect((await store.list()).where((r) => r.id == 'q_0001'), isEmpty);
    });

    test('type filter restricts the deletion', () async {
      await store.addNote(text: 'Shared sentence.');
      final question = await store.addQuestion(
        text: 'Shared sentence.',
        area: 'dev',
      );

      final result = await store.deleteRecordByText(
        'Shared sentence.',
        type: 'note',
      );

      expect(result.deletedIds, ['n_0001']);
      expect(await store.findById(question.id), isNotNull);
    });

    test('returns empty result when nothing matched', () async {
      final result = await store.deleteRecordByText('Does not exist.');
      expect(result.deleted, isFalse);
      expect(result.deletedIds, isEmpty);
    });

    test('leaves unrelated records untouched', () async {
      final other = await store.addNote(text: 'Totally different fact.');
      await store.deleteRecordByText('No match here.');

      expect(await store.findById(other.id), isNotNull);
    });
  });

  group('tombstone capture guard', () {
    test('skips re-adding deleted text by default', () async {
      final store = KBMemoryStore(InMemoryKbStorage(), source: 'agent');
      final doomed = await store.addNote(text: 'Garbage captured twice.');
      await store.deleteRecord(doomed.id);

      final again = await store.addNote(text: 'garbage captured TWICE.');

      expect(again.id, doomed.id); // would-be record, not written
      expect((await store.list(type: 'note')), isEmpty);
    });

    test('can be disabled with respectTombstones: false', () async {
      final store = KBMemoryStore(
        InMemoryKbStorage(),
        source: 'agent',
        respectTombstones: false,
      );
      final doomed = await store.addNote(text: 'Garbage captured twice.');
      await store.deleteRecord(doomed.id, rebuildGraph: false);

      await store.addNote(text: 'Garbage captured twice.');

      expect((await store.list(type: 'note')).length, 1);
    });

    test(
      'deleted text can be re-captured after ledger entry is gone',
      () async {
        final tmpDir = Directory.systemTemp.createTempSync('memory_tombstone_');
        addTearDown(() => tmpDir.deleteSync(recursive: true));
        final store = KBMemoryStore.file(tmpDir, source: 'agent');
        final doomed = await store.addNote(text: 'Recyclable fact.');
        await store.deleteRecord(doomed.id, rebuildGraph: false);
        // Simulate ledger cleanup (entries are capped/rotated in production).
        await store.storage.writeFile('DELETIONS.md', '');

        await store.addNote(text: 'Recyclable fact.');

        expect((await store.list(type: 'note')).length, 1);
      },
    );
  });

  group('consolidation resurrection guard', () {
    test('pending deletions are reported and marked consolidated', () async {
      final tmpDir = Directory.systemTemp.createTempSync('memory_consolid_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final store = KBMemoryStore.file(tmpDir, source: 'agent');
      final doomed = await store.addNote(text: 'Deleted between runs.');
      await store.deleteRecord(doomed.id, rebuildGraph: false);

      final pending = await MemoryDeletionService(
        store.storage,
      ).pendingDeletions();
      expect(pending, hasLength(1));
      expect(pending.single.id, doomed.id);
      expect(pending.single.text, contains('Deleted between runs'));

      final service = MemoryDeletionService(store.storage);
      await service.markConsolidated(pending.single.seq);
      expect(await service.pendingDeletions(), isEmpty);
    });

    test('consolidate receives deletion cleanup notices', () async {
      final tmpDir = Directory.systemTemp.createTempSync('memory_consolid2_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final provider = _RecordingProvider();
      final store = KBMemoryStore.file(tmpDir, provider: provider);
      await store.addNote(text: 'Surviving note.', area: 'dev', tags: ['x']);
      final doomed = await store.addNote(
        text: 'Deleted garbage note.',
        area: 'dev',
        tags: ['x'],
      );
      await store.deleteRecord(doomed.id, rebuildGraph: false);

      await store.consolidate();

      expect(provider.prompts, hasLength(1));
      expect(provider.prompts.single, contains('were deleted by the user'));
      // The deleted record is not part of the consolidation input records
      // (the only mention is the cleanup notice line).
      expect(
        provider.prompts.single,
        isNot(contains('1. [note] Deleted garbage note.')),
      );
      expect(provider.prompts.single, contains('- note ${doomed.id}:'));
    });

    test('consolidate aborts on a stale revision after delete', () async {
      final tmpDir = Directory.systemTemp.createTempSync('memory_consolid3_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final provider = _RecordingProvider();
      final store = KBMemoryStore.file(tmpDir, provider: provider);
      await store.addNote(text: 'Note A.', area: 'dev', tags: ['x']);
      await store.addNote(text: 'Note B.', area: 'dev', tags: ['x']);
      final revision = await store.readMemoryRevision();
      final doomed = await store.addNote(
        text: 'Deleted mid-flight note.',
        area: 'dev',
        tags: ['x'],
      );
      await store.deleteRecord(doomed.id, rebuildGraph: false);

      expect(
        () => store.consolidate(expectedRevisionHash: revision.hash),
        throwsA(isA<ConcurrentRevisionException>()),
      );
    });
  });

  group('deletion on sqlite backend', () {
    test('deletes by id and by text', () async {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      final store = KBMemoryStore(
        SqliteKbStorage(db),
        source: 'agent',
        respectTombstones: false,
      );

      final note = await store.addNote(text: 'Sqlite stored fact.');
      expect(await store.deleteRecord(note.id, rebuildGraph: false), isTrue);
      expect(await store.findById(note.id), isNull);

      final second = await store.addNote(text: 'Another sqlite fact.');
      final result = await store.deleteRecordByText(
        'Another sqlite fact.',
        rebuildGraph: false,
      );
      expect(result.deletedIds, [second.id]);
      expect(await store.findById(second.id), isNull);
    });
  });
}
