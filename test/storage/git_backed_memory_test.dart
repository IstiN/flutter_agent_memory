import 'dart:io';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:test/test.dart';

import '../fake_llm_provider.dart';

/// Tests for the "git-backed memory" guarantees: merge-friendly ids,
/// deterministic derivatives, union-mergeable deletion ledger, repo init,
/// and legacy-format backward compatibility.
void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('kb_gitbacked_');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  KBMemoryStore store({String? path}) => KBMemoryStore.file(
    path ?? tmpDir.path,
    provider: FakeLlmProvider(const {}),
    source: 'test',
  );

  group('merge-friendly ids', () {
    test('store allocates suffixed ids for all three types', () async {
      final s = store();
      final q = await s.addQuestion(text: 'How are ids allocated?');
      final a = await s.addAnswer(text: 'With a hash suffix.');
      final n = await s.addNote(text: 'Ids are merge-friendly.');
      expect(q.id, matches(r'^q_0001_[0-9a-f]{4}$'));
      expect(a.id, matches(r'^a_0001_[0-9a-f]{4}$'));
      expect(n.id, matches(r'^n_0001_[0-9a-f]{4}$'));
      // File is named after the id.
      expect(
        File('${tmpDir.path}/notes/${n.id}.md').existsSync(),
        isTrue,
      );
    });

    test('same text at same index yields the same id across stores', () async {
      final cloneA = await Directory.systemTemp.createTemp('kb_cloneA_');
      final cloneB = await Directory.systemTemp.createTemp('kb_cloneB_');
      addTearDown(() async {
        await cloneA.delete(recursive: true);
        await cloneB.delete(recursive: true);
      });
      final idA = (await store(path: cloneA.path).addNote(
        text: 'Shared fact from two branches.',
      )).id;
      final idB = (await store(path: cloneB.path).addNote(
        text: 'Shared fact from two branches.',
      )).id;
      expect(idA, idB);
    });

    test('index collision across clones produces two union-mergeable files', () async {
      final cloneA = await Directory.systemTemp.createTemp('kb_cloneA_');
      final cloneB = await Directory.systemTemp.createTemp('kb_cloneB_');
      addTearDown(() async {
        await cloneA.delete(recursive: true);
        await cloneB.delete(recursive: true);
      });
      final idA = (await store(path: cloneA.path).addNote(
        text: 'Fact from branch A.',
      )).id;
      final idB = (await store(path: cloneB.path).addNote(
        text: 'Fact from branch B.',
      )).id;
      expect(MemoryIdScheme.parseIndex(idA), 1);
      expect(MemoryIdScheme.parseIndex(idB), 1);
      expect(idA, isNot(idB));

      // Simulate git union merge: copy clone B's files into clone A.
      for (final entity in cloneB.listSync(recursive: true)) {
        if (entity is! File) continue;
        final rel = entity.path.substring(cloneB.path.length + 1);
        final target = File('${cloneA.path}/$rel');
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
      }
      final merged = store(path: cloneA.path);
      final ids = (await merged.list()).map((r) => r.id).toSet();
      expect(ids, containsAll([idA, idB]));
    });

    test('identical answers to different questions get different ids', () async {
      final s = store();
      final q1 = await s.addQuestion(text: 'Is the sky blue?');
      final q2 = await s.addQuestion(text: 'Is the grass green?');
      final a1 = await s.addAnswer(text: 'yes', answersQuestion: q1.id);
      final a2 = await s.addAnswer(text: 'yes', answersQuestion: q2.id);
      expect(MemoryIdScheme.parseIndex(a1.id), 1);
      expect(MemoryIdScheme.parseIndex(a2.id), 2);
      // Force the same index scenario through the scheme directly:
      final forced1 = MemoryIdScheme.allocate(
        'a',
        7,
        'yes',
        answersQuestion: q1.id,
      );
      final forced2 = MemoryIdScheme.allocate(
        'a',
        7,
        'yes',
        answersQuestion: q2.id,
      );
      expect(forced1, isNot(forced2));
    });
  });

  group('legacy backward compatibility', () {
    Future<void> writeLegacyNote(String name, String id, String text) async {
      await Directory('${tmpDir.path}/notes').create(recursive: true);
      await File('${tmpDir.path}/notes/$name.md').writeAsString('''
---
id: "$id"
author: "agent"
date: "2026-01-01T00:00:00Z"
area: "dev"
topics: []
tags: []
memory_type: fact
---

# Note: $id

$text
''');
    }

    test('legacy ids load, list, search, delete without conversion', () async {
      await writeLegacyNote('n_0001', 'n_0001', 'Legacy fact one.');
      await writeLegacyNote('n_0002', 'n_0002', 'Legacy fact two.');
      final s = store();
      final records = await s.list();
      expect(records.map((r) => r.id), containsAll(['n_0001', 'n_0002']));

      // Deleting a legacy record works and tombstones it.
      expect(await s.deleteRecord('n_0001'), isTrue);
      expect(await s.isDeleted('n_0001'), isTrue);
      expect(await s.hasDeletedText('Legacy fact one.'), isTrue);

      // Next allocation continues after the max legacy index.
      final added = await s.addNote(text: 'Brand new fact.');
      expect(MemoryIdScheme.parseIndex(added.id), 3);
      expect(MemoryIdScheme.isLegacy(added.id), isFalse);

      // Legacy files were never renamed.
      expect(File('${tmpDir.path}/notes/n_0002.md').existsSync(), isTrue);
    });

    test('mixed legacy and suffixed ids coexist in one store', () async {
      await writeLegacyNote('n_0001', 'n_0001', 'Old fact.');
      final s = store();
      final added = await s.addNote(text: 'New fact.');
      final records = await s.list();
      expect(records, hasLength(2));
      expect(
        records.map((r) => r.id),
        containsAll(['n_0001', added.id]),
      );
    });
  });

  group('deterministic GRAPH.md', () {
    test('delete + rebuild yields byte-identical graph', () async {
      final s = store();
      await s.addNote(text: 'Node one.');
      await s.addNote(text: 'Node two.');
      await s.buildGraph();
      final graphFile = File('${tmpDir.path}/GRAPH.md');
      final first = await graphFile.readAsBytes();
      await graphFile.delete();
      await s.buildGraph();
      final second = await graphFile.readAsBytes();
      expect(second, first);
    });
  });

  group('revision service without MEMORY.revision file', () {
    test('fresh clone (no revision file) uses content hash path', () async {
      final s = store();
      await s.storage.writeFile('MEMORY.md', 'summary from clone');
      final revision = await s.readMemoryRevision();
      expect(revision.hash, isNotEmpty);
      expect(
        File('${tmpDir.path}/MEMORY.revision').existsSync(),
        isFalse,
      );
      // Stable while content is stable.
      final again = await s.readMemoryRevision();
      expect(again.hash, revision.hash);
    });
  });

  group('DELETIONS.md union-merge tolerance', () {
    test('ledger has no count line and parses duplicated union output', () async {
      final s = store();
      final n1 = await s.addNote(text: 'Delete me one.');
      final n2 = await s.addNote(text: 'Delete me two.');
      await s.deleteRecord(n1.id);
      await s.deleteRecord(n2.id);

      final ledger = (await s.storage.readFile('DELETIONS.md'))!;
      expect(ledger, isNot(contains('count:')));

      // Simulate `git merge=union`: both sides' headers + entries repeated,
      // out of order, with diverging cursors.
      final lines = ledger.split('\n').where((l) => l.trim().isNotEmpty);
      final entryLines = lines.where((l) => l.startsWith('- seq:')).toList();
      final union = StringBuffer()
        ..writeln('---')
        ..writeln('consolidatedUpTo: 0')
        ..writeln('---')
        ..writeln(entryLines[1])
        ..writeln(entryLines[0])
        ..writeln(entryLines[1]) // duplicate from the other side
        ..writeln('---')
        ..writeln('consolidatedUpTo: 1')
        ..writeln('---');
      await s.storage.writeFile('DELETIONS.md', union.toString());

      final service = MemoryDeletionService(s.storage);
      final pending = await service.pendingDeletions();
      // Cursor is max(0, 1) = 1, so only seq 2 is pending.
      expect(pending, hasLength(1));
      expect(pending.single.seq, 2);
      // Deduped by (seq, id): both deletions are known exactly once.
      expect(await service.isDeleted(n1.id), isTrue);
      expect(await service.isDeleted(n2.id), isTrue);
    });
  });

  group('MemoryRepoInit', () {
    test('writes .gitignore and .gitattributes with required lines', () async {
      final s = store();
      final result = await MemoryRepoInit(s.storage).ensureGitSupport();
      expect(result.gitignoreUpdated, isTrue);
      expect(result.gitattributesUpdated, isTrue);

      final gitignore = (await s.storage.readFile('.gitignore'))!;
      for (final f in MemoryRepoInit.derivativeFiles) {
        expect(gitignore, contains(f));
      }
      final gitattributes = (await s.storage.readFile('.gitattributes'))!;
      expect(gitattributes, contains('DELETIONS.md merge=union'));
    });

    test('is idempotent and preserves user content', () async {
      final s = store();
      await s.storage.writeFile('.gitignore', 'my-own-file.txt\n');
      final first = await MemoryRepoInit(s.storage).ensureGitSupport();
      expect(first.gitignoreUpdated, isTrue);
      final second = await MemoryRepoInit(s.storage).ensureGitSupport();
      expect(second.alreadyConfigured, isTrue);
      final gitignore = (await s.storage.readFile('.gitignore'))!;
      expect(gitignore, contains('my-own-file.txt'));
      expect(gitignore.indexOf('GRAPH.md'), gitignore.lastIndexOf('GRAPH.md'));
    });
  });
}
