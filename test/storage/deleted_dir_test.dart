import 'dart:io';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:test/test.dart';

import '../fake_llm_provider.dart';

/// The per-record `deleted/` deletion record: one deterministic file per
/// deletion, so concurrent agents on different git branches can never
/// conflict, and consolidation progress is a local set difference instead
/// of a shared global cursor.
void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('kb_deleteddir_');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  KBMemoryStore store({String? path}) => KBMemoryStore.file(
    path ?? tmpDir.path,
    provider: FakeLlmProvider(const {}),
    source: 'test',
  );

  group('deleted/ record files', () {
    test('delete writes one deterministic per-record file', () async {
      final s = store();
      final note = await s.addNote(text: 'Fact destined for deletion.');
      await s.deleteRecord(note.id);

      final files = await s.storage.listFilePaths('deleted');
      expect(files, hasLength(1));
      expect(files.single, startsWith('deleted/${note.id}_'));
      expect(files.single, endsWith('.md'));

      final content = (await s.storage.readFile(files.single))!;
      expect(content, contains('id: ${note.id}'));
      expect(content, contains('Fact destined for deletion.'));
      // Deterministic: no wall-clock fields.
      expect(content, isNot(contains('deletedAt')));
    });

    test(
      'same deletion from two independent stores is byte-identical',
      () async {
        final cloneA = await Directory.systemTemp.createTemp('kb_cloneA_');
        final cloneB = await Directory.systemTemp.createTemp('kb_cloneB_');
        addTearDown(() async {
          await cloneA.delete(recursive: true);
          await cloneB.delete(recursive: true);
        });
        final noteA = await store(
          path: cloneA.path,
        ).addNote(text: 'Shared deletion from two branches.');
        final noteB = await store(
          path: cloneB.path,
        ).addNote(text: 'Shared deletion from two branches.');
        expect(noteA.id, noteB.id);

        await store(path: cloneA.path).deleteRecord(noteA.id);
        await store(path: cloneB.path).deleteRecord(noteB.id);

        // Same file name, same bytes: git merges the two branches trivially.
        final filesA = await store(
          path: cloneA.path,
        ).storage.listFilePaths('deleted');
        final filesB = await store(
          path: cloneB.path,
        ).storage.listFilePaths('deleted');
        expect(filesA, filesB);
        expect(
          await store(path: cloneA.path).storage.readFile(filesA.single),
          await store(path: cloneB.path).storage.readFile(filesB.single),
        );
      },
    );

    test('different deletions are independent files', () async {
      final s = store();
      final a = await s.addNote(text: 'First doomed fact.');
      final b = await s.addQuestion(text: 'Second doomed fact?');
      await s.deleteRecord(a.id);
      await s.deleteRecord(b.id);

      final files = await s.storage.listFilePaths('deleted');
      expect(files, hasLength(2));
      expect(files.any((f) => f.startsWith('deleted/${a.id}_')), isTrue);
      expect(files.any((f) => f.startsWith('deleted/${b.id}_')), isTrue);
      expect(await s.isDeleted(a.id), isTrue);
      expect(await s.isDeleted(b.id), isTrue);
      expect(await s.hasDeletedText('First doomed fact.'), isTrue);
      expect(await s.hasDeletedText('Second doomed fact?'), isTrue);
      expect(await s.hasDeletedText('Never deleted fact.'), isFalse);
    });

    test('double delete keeps a single deleted/ file', () async {
      final s = store();
      final note = await s.addNote(text: 'Delete me once.');
      await s.deleteRecord(note.id);
      await s.deleteRecord(note.id);
      expect(await s.storage.listFilePaths('deleted'), hasLength(1));
    });
  });

  group('consolidation progress as set difference', () {
    test(
      'unprocessedDeletions reports new deletions, marker stops repeats',
      () async {
        final s = store();
        final service = MemoryDeletionService(s.storage);
        expect(await service.unprocessedDeletions(), isEmpty);

        final n1 = await s.addNote(text: 'First unprocessed.');
        await s.deleteRecord(n1.id);
        final pending1 = await service.unprocessedDeletions();
        expect(pending1, hasLength(1));
        expect(pending1.single.id, n1.id);
        expect(pending1.single.text, 'First unprocessed.');

        await service.markDeletionsProcessed(pending1);
        expect(await service.unprocessedDeletions(), isEmpty);

        // A deletion arriving later (e.g. merged from another branch) is
        // still reported — unlike the legacy seq cursor, nothing is lost.
        final n2 = await s.addNote(text: 'Second unprocessed.');
        await s.deleteRecord(n2.id);
        final pending2 = await service.unprocessedDeletions();
        expect(pending2, hasLength(1));
        expect(pending2.single.id, n2.id);
      },
    );

    test('marker is incremental and tolerant of unordered content', () async {
      final s = store();
      final service = MemoryDeletionService(s.storage);
      final n1 = await s.addNote(text: 'Alpha.');
      final n2 = await s.addNote(text: 'Beta.');
      await s.deleteRecord(n1.id);
      await s.deleteRecord(n2.id);

      final all = await service.unprocessedDeletions();
      expect(all, hasLength(2));
      await service.markDeletionsProcessed([all.first]);
      final rest = await service.unprocessedDeletions();
      expect(rest, hasLength(1));
      expect(rest.single.id, all.last.id);
    });

    test('markDeletionsProcessed with empty list is a no-op', () async {
      final s = store();
      final service = MemoryDeletionService(s.storage);
      await service.markDeletionsProcessed(const []);
      expect(await s.storage.readFile('.last_deletions'), isNull);
    });
  });

  group('repo init integration', () {
    test(
      '.gitignore excludes .last_deletions; .gitattributes unions deleted/',
      () async {
        final s = store();
        await MemoryRepoInit(s.storage).ensureGitSupport();
        final gitignore = (await s.storage.readFile('.gitignore'))!;
        expect(gitignore, contains('.last_deletions'));
        final gitattributes = (await s.storage.readFile('.gitattributes'))!;
        expect(gitattributes, contains('deleted/*.md merge=union'));
      },
    );
  });

  group('legacy compatibility', () {
    test(
      'isDeleted/hasDeletedText still honour a legacy-only ledger',
      () async {
        final s = store();
        // Simulate a store from before the deleted/ mechanism: ledger only,
        // entity already unlinked.
        await s.storage.writeFile('DELETIONS.md', '''
---
consolidatedUpTo: 0
---
- seq: 1 | id: n_0001 | type: note | fingerprint: abc123 | deletedAt: 2026-01-01T00:00:00Z | text: old style fact
''');
        final service = MemoryDeletionService(s.storage);
        expect(await service.isDeleted('n_0001'), isTrue);
      },
    );
  });
}
