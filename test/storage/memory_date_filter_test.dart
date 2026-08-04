import 'dart:io';

import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;
  late KBMemoryStore store;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('memory_date_filter_');
    store = KBMemoryStore.file(tmpDir, source: 'agent');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('list asOf includes records created before or at date', () async {
    await store.addNote(text: 'Old note.', area: 'dev', tags: ['x']);
    await store.addNote(text: 'New note.', area: 'dev', tags: ['x']);

    final now = DateTime.now().toUtc();
    final all = await store.list(type: 'note', asOf: now.add(const Duration(days: 365)));
    expect(all.length, 2);

    final onlyOld = await store.list(type: 'note', asOf: now);
    expect(onlyOld.length, 2);
  });

  test('asOf excludes notes with validFrom in the future', () async {
    final future = DateTime.now().toUtc().add(const Duration(days: 7));
    await store.addNote(
      text: 'Future note.',
      area: 'dev',
      tags: ['x'],
      validFrom: future.toIso8601String(),
    );

    final now = DateTime.now().toUtc();
    final records = await store.list(type: 'note', asOf: now);
    expect(records, isEmpty);
  });

  test('asOf excludes notes with validUntil in the past', () async {
    final past = DateTime.now().toUtc().subtract(const Duration(days: 7));
    await store.addNote(
      text: 'Expired note.',
      area: 'dev',
      tags: ['x'],
      validUntil: past.toIso8601String(),
    );

    final now = DateTime.now().toUtc();
    final records = await store.list(type: 'note', asOf: now);
    expect(records, isEmpty);
  });
}
