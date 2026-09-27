import 'dart:io';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:test/test.dart';

import '../fake_llm_provider.dart';

/// Tombstone-in-place deletion semantics for the git-backed file storage:
/// deletions rewrite entity files instead of unlinking them, so git never
/// sees a delete/modify conflict for memory records.
void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('kb_tombstone_');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  KBMemoryStore store({String? path}) => KBMemoryStore.file(
    path ?? tmpDir.path,
    provider: FakeLlmProvider(const {}),
    source: 'test',
  );

  group('tombstone-in-place deletion', () {
    test(
      'deleted record stays on disk as a tombstone but reads as absent',
      () async {
        final s = store();
        final note = await s.addNote(text: 'Fact to delete.');
        final file = File('${tmpDir.path}/notes/${note.id}.md');
        expect(file.existsSync(), isTrue);

        expect(await s.deleteRecord(note.id), isTrue);

        // The file is NOT unlinked — it is rewritten in place.
        expect(file.existsSync(), isTrue);
        final content = await file.readAsString();
        expect(FileKbStorage.isTombstoneContent(content), isTrue);
        expect(content, contains('tombstone: true'));
        expect(content, contains(note.id));

        // Readers see the entity as deleted.
        expect(await s.storage.readEntity('note', note.id), isNull);
        expect(await s.isDeleted(note.id), isTrue);
        expect(await s.hasDeletedText('Fact to delete.'), isTrue);
        final records = await s.list();
        expect(records.map((r) => r.id), isNot(contains(note.id)));
      },
    );

    test('delete by text tombstones matches and keeps non-matches', () async {
      final s = store();
      final hit = await s.addNote(text: 'Duplicate fact.');
      await s.addNote(text: 'Unrelated fact.');
      final result = await s.deleteRecordByText('Duplicate fact.');
      expect(result.deletedIds, [hit.id]);
      expect(
        FileKbStorage.isTombstoneContent(
          File('${tmpDir.path}/notes/${hit.id}.md').readAsStringSync(),
        ),
        isTrue,
      );
      final records = await s.list();
      expect(records, hasLength(1));
      expect(records.single.text, 'Unrelated fact.');
    });

    test('tombstoned ids still occupy their index (no id reuse)', () async {
      final s = store();
      final n1 = await s.addNote(text: 'First.');
      final n2 = await s.addNote(text: 'Second.');
      await s.deleteRecord(n1.id);
      final n3 = await s.addNote(text: 'Third.');
      // n3 gets a fresh index even though n1's slot looks free: the
      // tombstone file keeps the id alive for max-id computation.
      expect(
        MemoryIdScheme.parseIndex(n3.id),
        greaterThan(MemoryIdScheme.parseIndex(n2.id) ?? 0),
      );
      expect(n3.id, isNot(n1.id));
    });

    test('double delete is idempotent and keeps one tombstone', () async {
      final s = store();
      final note = await s.addNote(text: 'Delete twice.');
      expect(await s.deleteRecord(note.id), isTrue);
      expect(await s.deleteRecord(note.id), isFalse);
      expect(File('${tmpDir.path}/notes/${note.id}.md').existsSync(), isTrue);
    });

    test('purge physically removes tombstones and is then a no-op', () async {
      final s = store();
      final keep = await s.addNote(text: 'Keep me.');
      final gone = await s.addNote(text: 'Purge me.');
      await s.deleteRecord(gone.id);

      final purged = await s.purgeTombstones();
      expect(purged, [gone.id]);
      expect(File('${tmpDir.path}/notes/${gone.id}.md').existsSync(), isFalse);
      // Live records are untouched and still readable.
      expect(File('${tmpDir.path}/notes/${keep.id}.md').existsSync(), isTrue);
      expect(await s.storage.readEntity('note', keep.id), isNotNull);
      // Deletion history survives the purge via the ledger.
      expect(await s.isDeleted(gone.id), isTrue);
      expect(await s.hasDeletedText('Purge me.'), isTrue);
      expect(await s.purgeTombstones(), isEmpty);
    });
  });

  group('union-merge tolerance', () {
    test(
      'tombstone marker survives a worst-case union of both sides',
      () async {
        // git merge-file --union on two full-file rewrites concatenates the
        // conflicting hunks: the file ends up containing BOTH the tombstone
        // and the other branch's edit. The marker must still win.
        final s = store();
        final note = await s.addNote(text: 'Concurrent target.');
        final original = await File(
          '${tmpDir.path}/notes/${note.id}.md',
        ).readAsString();

        await s.deleteRecord(note.id);
        final tombstone = await File(
          '${tmpDir.path}/notes/${note.id}.md',
        ).readAsString();

        final modified = original.replaceFirst(
          'Concurrent target.',
          'Concurrent target, edited on another branch.',
        );

        // Simulated union merge output: both variants present.
        final unioned = '$tombstone\n$modified';
        expect(FileKbStorage.isTombstoneContent(unioned), isTrue);

        await File('${tmpDir.path}/notes/${note.id}.md').writeAsString(unioned);
        expect(await s.storage.readEntity('note', note.id), isNull);
        expect(await s.isDeleted(note.id), isTrue);
      },
    );

    test('tombstone vs tombstone union stays a valid tombstone', () async {
      final s = store();
      final note = await s.addNote(text: 'Delete from both branches.');
      await s.deleteRecord(note.id);
      final tombA = await File(
        '${tmpDir.path}/notes/${note.id}.md',
      ).readAsString();

      // The other branch deleted the same record at a different time: its
      // tombstone differs only in the timestamp. A union merge of the two
      // tombstones must still be recognised as deleted.
      final tombB = FileKbStorage.tombstoneContentFor(
        note.id,
        '2026-09-27T12:00:00Z',
      );
      expect(tombB, isNot(tombA));

      expect(FileKbStorage.isTombstoneContent('$tombA\n$tombB'), isTrue);
      expect(FileKbStorage.isTombstoneContent('$tombB\n$tombA'), isTrue);
    });
  });

  group('MemoryRepoInit merge drivers', () {
    test('.gitattributes unions entity files and the ledger', () async {
      final s = store();
      await MemoryRepoInit(s.storage).ensureGitSupport();
      final gitattributes = (await s.storage.readFile('.gitattributes'))!;
      for (final line in MemoryRepoInit.mergeDriverLines) {
        expect(gitattributes, contains(line));
      }
    });
  });
}
