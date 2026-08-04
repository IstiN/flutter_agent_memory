import 'package:flutter_agent_memory/src/models/consolidation_result.dart';
import 'package:flutter_agent_memory/src/storage/in_memory_kb_storage.dart';
import 'package:flutter_agent_memory/src/storage/memory/memory_consolidation_writer.dart';
import 'package:flutter_agent_memory/src/storage/memory/memory_revision_service.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryKbStorage storage;
  late MemoryRevisionService revision;
  late MemoryConsolidationWriter writer;

  setUp(() {
    storage = InMemoryKbStorage();
    revision = MemoryRevisionService(storage);
    writer = MemoryConsolidationWriter(storage, revision);
  });

  test('writes summary directly when no expected hash', () async {
    final result = ConsolidationResult(
      summary: 'Global summary.',
      skills: [],
    );
    await writer.write(result);

    expect(storage.readFile('MEMORY.md'), 'Global summary.');
  });

  test('uses revision service when expected hash is provided', () async {
    final current = await revision.read();
    final result = ConsolidationResult(
      summary: 'Updated summary.',
      skills: [],
    );
    await writer.write(result, expectedRevisionHash: current.hash);

    expect(storage.readFile('MEMORY.md'), 'Updated summary.');
  });

  test('throws on concurrent revision mismatch', () async {
    storage.writeFile('MEMORY.md', 'other');
    final result = ConsolidationResult(
      summary: 'Updated summary.',
      skills: [],
    );
    expect(
      () => writer.write(result, expectedRevisionHash: 'stale-hash'),
      throwsA(isA<ConcurrentRevisionException>()),
    );
  });

  test('writes skill cards and clears old slots', () async {
    storage.writeFile('skills/sk_0001.md', 'old skill');
    final result = ConsolidationResult(
      summary: '',
      skills: [
        SkillCard(id: 'sk_1', title: 'Skill One', instruction: 'Do one.'),
        SkillCard(id: 'sk_2', title: 'Skill Two', instruction: 'Do two.'),
      ],
    );
    await writer.write(result);

    final card1 = storage.readFile('skills/sk_0001.md')!;
    expect(card1, contains('Skill One'));
    expect(card1, contains('Do one.'));

    final card2 = storage.readFile('skills/sk_0002.md')!;
    expect(card2, contains('Skill Two'));
    expect(card2, contains('Do two.'));

    // The old slot is overwritten before the new cards are written.
    // Because the loop breaks on the first empty slot after writing cards,
    // sk_0001 no longer contains the old content.
    expect(card1, isNot(contains('old skill')));
  });
}
