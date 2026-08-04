import 'dart:io';

import 'package:flutter_agent_memory/src/models/memory_level.dart';
import 'package:flutter_agent_memory/src/storage/in_memory_kb_storage.dart';
import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:test/test.dart';

void main() {
  group('capture-time deduplication', () {
    late KBMemoryStore store;

    setUp(() {
      store = KBMemoryStore(InMemoryKbStorage(), source: 'agent');
    });

    test('skips duplicate notes', () async {
      await store.addNote(text: 'My name is Vova.', area: 'general', tags: ['x']);
      await store.addNote(text: '  my name is Vova.  ', area: 'general', tags: ['x']);
      final notes = await store.list(type: 'note');
      expect(notes.length, 1);
    });

    test('allows different memory levels for same text', () async {
      await store.addNote(text: 'Insight.', area: 'general', tags: ['x'], level: MemoryLevel.raw);
      await store.addNote(text: 'Insight.', area: 'general', tags: ['x'], level: MemoryLevel.consolidated);
      final notes = await store.list(type: 'note');
      expect(notes.length, 2);
    });

    test('dedupe can be disabled', () async {
      final store2 = KBMemoryStore(
        InMemoryKbStorage(),
        source: 'agent',
        deduplicateOnCapture: false,
      );
      await store2.addNote(text: 'Fact.', area: 'general', tags: ['x']);
      await store2.addNote(text: 'Fact.', area: 'general', tags: ['x']);
      expect((await store2.list(type: 'note')).length, 2);
    });
  });

  group('revision tokens', () {
    test('readMemoryRevision returns stable hash', () async {
      final store = KBMemoryStore(InMemoryKbStorage(), source: 'agent');
      final rev1 = await store.readMemoryRevision();
      expect(rev1.hash, revisionHash(''));
      await store.storage.writeFile('MEMORY.md', 'updated summary');
      final rev2 = await store.readMemoryRevision();
      expect(rev2.hash, isNot(rev1.hash));
    });

    test('writeMemoryRevision rejects stale expected hash', () async {
      final store = KBMemoryStore(InMemoryKbStorage(), source: 'agent');
      await store.storage.writeFile('MEMORY.md', 'first');
      final rev = await store.readMemoryRevision();
      await store.storage.writeFile('MEMORY.md', 'second');
      final ok = await store.writeMemoryRevision('third', rev.hash);
      expect(ok, isFalse);
    });

    test('writeMemoryRevision accepts matching expected hash', () async {
      final store = KBMemoryStore(InMemoryKbStorage(), source: 'agent');
      await store.storage.writeFile('MEMORY.md', 'first');
      final rev = await store.readMemoryRevision();
      final ok = await store.writeMemoryRevision('second', rev.hash);
      expect(ok, isTrue);
      expect(await store.storage.readFile('MEMORY.md'), 'second');
    });
  });

  group('memory level maintenance', () {
    test('promotes raw notes older than threshold', () async {
      final tmpDir = Directory.systemTemp.createTempSync('memory_features_');
      final store = KBMemoryStore.file(
        tmpDir,
        source: 'agent',
        promotionPolicy: const MemoryPromotionPolicy(
          rawToConsolidatedAfter: Duration(seconds: 0),
          rawExpiryAfter: Duration(days: 365),
          consolidatedToConceptAfter: Duration(days: 365),
        ),
      );

      await store.addNote(text: 'Raw fact.', area: 'general', tags: ['x']);
      expect((await store.list(type: 'note')).first.note!.level, MemoryLevel.raw);
      final changed = await store.maintainMemoryLevels();
      expect(changed, 1);
      expect((await store.list(type: 'note')).first.note!.level, MemoryLevel.consolidated);

      tmpDir.deleteSync(recursive: true);
    });

    test('expires raw notes older than expiry threshold', () async {
      final tmpDir = Directory.systemTemp.createTempSync('memory_features_');
      final store = KBMemoryStore.file(
        tmpDir,
        source: 'agent',
        promotionPolicy: const MemoryPromotionPolicy(
          rawToConsolidatedAfter: Duration(days: 365),
          rawExpiryAfter: Duration(seconds: 0),
          consolidatedToConceptAfter: Duration(days: 365),
        ),
      );

      await store.addNote(text: 'Stale fact.', area: 'general', tags: ['x']);
      final changed = await store.maintainMemoryLevels();
      expect(changed, 1);
      expect(await store.list(type: 'note'), isEmpty);

      tmpDir.deleteSync(recursive: true);
    });

    test('promotes consolidated notes to concept', () async {
      final tmpDir = Directory.systemTemp.createTempSync('memory_features_');
      final store = KBMemoryStore.file(
        tmpDir,
        source: 'agent',
        promotionPolicy: const MemoryPromotionPolicy(
          rawToConsolidatedAfter: Duration(days: 365),
          rawExpiryAfter: Duration(days: 365),
          consolidatedToConceptAfter: Duration(seconds: 0),
        ),
      );

      await store.addNote(
        text: 'Stable fact.',
        area: 'general',
        tags: ['x'],
        level: MemoryLevel.consolidated,
      );
      final changed = await store.maintainMemoryLevels();
      expect(changed, 1);
      expect(
        (await store.list(type: 'note')).first.note!.level,
        MemoryLevel.concept,
      );

      tmpDir.deleteSync(recursive: true);
    });
  });

  group('cross-scope provenance', () {
    test('copies note into target store with provenance', () async {
      final source = KBMemoryStore(InMemoryKbStorage(), source: 'agent');
      final personal = KBMemoryStore(InMemoryKbStorage(), source: 'agent');

      final note = await source.addNote(
        text: 'Use Riverpod for state',
        area: 'development',
        tags: ['flutter'],
      );

      final copied = await source.copyNoteToScope(
        note.id,
        personal,
        sourceScope: 'project-atlas',
      );
      expect(copied, isNotNull);
      expect((await personal.list(type: 'note')).first.text, contains('(said in project-atlas)'));
    });
  });
}
