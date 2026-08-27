import 'package:flutter_agent_memory/src/models/note.dart';
import 'package:flutter_agent_memory/src/models/relation.dart';
import 'package:flutter_agent_memory/src/storage/kb_file_parser.dart';
import 'package:flutter_agent_memory/src/storage/kb_markdown_renderer.dart';
import 'package:test/test.dart';

void main() {
  group('KbMarkdownRenderer.buildEntityTags', () {
    const renderer = KbMarkdownRenderer();

    test('adds system tags when missing', () {
      final tags = renderer.buildEntityTags(['custom'], 'agent', '#note');
      expect(tags, ['#note', '#source_agent', 'custom']);
    });

    test('preserves system tags already present (re-render safety)', () {
      // Notes are re-rendered on every update (relations, promote, access
      // tracking). System tags must survive that round trip.
      final tags = renderer.buildEntityTags(
        ['#note', '#source_alice', 'release'],
        'alice',
        '#note',
      );
      expect(tags, ['#note', '#source_alice', 'release']);
    });

    test('does not duplicate the entity tag', () {
      final tags = renderer.buildEntityTags(['#note'], 'agent', '#note');
      expect(tags.where((t) => t == '#note'), hasLength(1));
    });

    test('re-rendering adopts the current store scope, without duplicates', () {
      // A note copied from another scope carries the old source tag; the
      // rendering store's own scope always wins, exactly one source tag.
      final tags = renderer.buildEntityTags(
        ['#note', '#source_original', 'x'],
        'other',
        '#note',
      );
      expect(tags, ['#note', '#source_other', 'x']);
      expect(tags.where((t) => t.startsWith('#source_')), hasLength(1));
    });
  });

  test('note round trip keeps tags and relations', () {
    const renderer = KbMarkdownRenderer();
    const note = Note(
      id: 'n_0001',
      text: 'Round trip.',
      area: 'dev',
      topics: ['dart'],
      tags: ['#note', '#source_agent', 'release'],
      author: 'agent',
      date: '2025-01-01T00:00:00Z',
      answersQuestions: [],
      links: [],
      importance: 0.9,
      memoryType: 'fact',
      level: 2,
      relations: [
        Relation(
          source: 'n_0001',
          target: 'a_0001',
          type: RelationType.supports,
        ),
      ],
    );

    final markdown = renderer.renderNote(note, 'agent');
    final parsed = KBFileParser().parseNote(markdown);

    expect(parsed.tags, containsAll(['#note', '#source_agent', 'release']));
    expect(parsed.relations, hasLength(1));
    expect(parsed.relations.single.target, 'a_0001');
    expect(parsed.level, 2);
  });
}
