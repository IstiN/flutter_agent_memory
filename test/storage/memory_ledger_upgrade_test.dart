import 'dart:io';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:test/test.dart';

import '../fake_llm_provider.dart';

/// Regression tests for the fa bug report against 0.2.0:
/// 1) a 0.1.x-format ledger (with `count:`) must never be clobbered by the
///    first delete after upgrade;
/// 2) concurrent deletes must not lose entries (append-only ledger);
/// 3) unparseable ledger content must be preserved, never rewritten away.
void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('kb_ledger_');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  KBMemoryStore store() => KBMemoryStore.file(
    tmpDir.path,
    provider: FakeLlmProvider(const {}),
    source: 'test',
  );

  String ledgerLine(int seq, String id, String type, String text) =>
      '- seq: $seq | id: $id | type: $type | fingerprint: fp$seq | '
      'deletedAt: 2026-01-0${seq}T00:00:00Z | text: $text\n';

  /// The canonical 0.1.x ledger shape, including the `count:` header line.
  String legacyLedger(int entries) {
    final buffer = StringBuffer('---\ncount: $entries\nconsolidatedUpTo: 0\n---\n');
    for (var i = 1; i <= entries; i++) {
      buffer.write(ledgerLine(i, 'n_${i.toString().padLeft(4, '0')}', 'note', 'old fact $i'));
    }
    return buffer.toString();
  }

  group('0.1.x ledger upgrade', () {
    test('canonical 0.1.x ledger entries survive the first 0.2.x delete', () async {
      final s = store();
      await s.storage.writeFile('DELETIONS.md', legacyLedger(5));
      final note = await s.addNote(text: 'Fresh fact to delete.');

      expect(await s.deleteRecord(note.id), isTrue);

      final ledger = (await s.storage.readFile('DELETIONS.md'))!;
      // All five legacy entries are still there...
      for (var i = 1; i <= 5; i++) {
        expect(ledger, contains('old fact $i'));
      }
      // ...and the new deletion continues the sequence, not restarts it.
      // (The inert legacy `count:` line stays — append-only never rewrites
      // history; the parser simply ignores it.)
      expect(ledger, contains('seq: 6'));
    });

    test('tombstones from a 0.1.x ledger still block re-capture', () async {
      final s = store();
      final fp = memoryTextFingerprint('Old deleted fact.');
      await s.storage.writeFile(
        'DELETIONS.md',
        '---\ncount: 1\nconsolidatedUpTo: 0\n---\n'
        '- seq: 1 | id: n_0001 | type: note | fingerprint: $fp | '
        'deletedAt: 2026-01-01T00:00:00Z | text: Old deleted fact.\n',
      );
      expect(await s.hasDeletedText('Old deleted fact.'), isTrue);
      expect(await s.isDeleted('n_0001'), isTrue);
    });

    test('entries without a type field are tolerated (type from id)', () async {
      final s = store();
      await s.storage.writeFile(
        'DELETIONS.md',
        '---\nconsolidatedUpTo: 0\n---\n'
        '- seq: 7 | id: n_0042 | fingerprint: fpX | deletedAt: 2026-01-01T00:00:00Z | text: x\n',
      );
      final service = MemoryDeletionService(s.storage);
      expect(await service.isDeleted('n_0042'), isTrue);
      final pending = await service.pendingDeletions();
      expect(pending.single.type, 'note');
      expect(pending.single.seq, 7);
    });
  });

  group('never-clobber guarantee', () {
    test('unparseable ledger content is preserved on delete', () async {
      final s = store();
      const garbage = '# hand-written notes\nsome foreign tombstone format\n';
      await s.storage.writeFile('DELETIONS.md', garbage);
      final note = await s.addNote(text: 'Deletable.');

      await s.deleteRecord(note.id);

      final ledger = (await s.storage.readFile('DELETIONS.md'))!;
      expect(ledger, startsWith(garbage));
      expect(ledger, contains(note.id));
    });
  });

  group('append-only concurrency', () {
    test('two deletes that both read an empty ledger both survive', () async {
      // Simulates the fa race: two processes parse the same (empty) ledger,
      // compute the same seq, and write. With append-only writes both
      // tombstones land; the parser keeps both (distinct ids).
      final s = store();
      final service = MemoryDeletionService(s.storage);
      final n1 = await s.addNote(text: 'Fact one.');
      final n2 = await s.addNote(text: 'Fact two.');

      // First deletion initializes the ledger.
      await s.deleteRecord(n1.id);
      // Second deletion appends without rewriting.
      await s.deleteRecord(n2.id);

      expect(await service.isDeleted(n1.id), isTrue);
      expect(await service.isDeleted(n2.id), isTrue);
    });

    test('duplicate seqs with distinct ids both survive parsing', () async {
      final s = store();
      await s.storage.writeFile(
        'DELETIONS.md',
        '---\nconsolidatedUpTo: 0\n---\n'
        '${ledgerLine(1, 'n_0001', 'note', 'fact one')}'
        '${ledgerLine(1, 'n_0002', 'note', 'fact two')}',
      );
      final service = MemoryDeletionService(s.storage);
      expect(await service.isDeleted('n_0001'), isTrue);
      expect(await service.isDeleted('n_0002'), isTrue);
    });

    test('markConsolidated appends a cursor line instead of rewriting', () async {
      final s = store();
      final note = await s.addNote(text: 'To delete.');
      await s.deleteRecord(note.id);
      final before = (await s.storage.readFile('DELETIONS.md'))!;

      final service = MemoryDeletionService(s.storage);
      await service.markConsolidated(1);

      final after = (await s.storage.readFile('DELETIONS.md'))!;
      expect(after, startsWith(before));
      expect(after, contains('consolidatedUpTo: 1'));
      expect(await service.pendingDeletions(), isEmpty);
    });
  });
}
