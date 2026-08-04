import 'package:flutter_agent_memory/src/models/answer.dart';
import 'package:flutter_agent_memory/src/models/note.dart';
import 'package:flutter_agent_memory/src/models/question.dart';
import 'package:flutter_agent_memory/src/storage/in_memory_kb_storage.dart';
import 'package:flutter_agent_memory/src/storage/kb_file_parser.dart';
import 'package:flutter_agent_memory/src/storage/kb_markdown_renderer.dart';
import 'package:flutter_agent_memory/src/storage/memory/memory_dedup_service.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryKbStorage storage;
  late MemoryDedupService dedup;
  const renderer = KbMarkdownRenderer();

  setUp(() {
    storage = InMemoryKbStorage();
    dedup = MemoryDedupService(storage, KBFileParser());
  });

  test('finds duplicate question', () async {
    final q = Question(
      id: 'q_0001',
      author: 'A',
      text: 'How to test Dart?',
      date: '2024-01-01',
      area: 'dev',
      topics: const ['dart'],
      tags: const ['dart'],
      links: const [],
    );
    storage.writeEntity('question', q.id, renderer.renderQuestion(q, 'agent'));

    expect(await dedup.hasDuplicateQuestion('How to test Dart?'), isTrue);
    expect(await dedup.hasDuplicateQuestion('Different text'), isFalse);
  });

  test('finds duplicate answer', () async {
    final a = Answer(
      id: 'a_0001',
      author: 'B',
      text: 'Use the test package.',
      date: '2024-01-01',
      area: 'dev',
      topics: const ['dart'],
      tags: const ['dart'],
      quality: 0.9,
      links: const [],
    );
    storage.writeEntity('answer', a.id, renderer.renderAnswer(a, 'agent'));

    expect(await dedup.hasDuplicateAnswer('Use the test package.'), isTrue);
    expect(await dedup.hasDuplicateAnswer('Different answer'), isFalse);
  });

  test('finds duplicate note', () async {
    final n = Note(
      id: 'n_0001',
      author: 'C',
      text: 'Remember to analyze.',
      date: '2024-01-01',
      area: 'dev',
      topics: const ['dart'],
      tags: const ['dart'],
      answersQuestions: const [],
      links: const [],
    );
    storage.writeEntity('note', n.id, renderer.renderNote(n, 'agent'));

    expect(
      await dedup.hasDuplicateNote(
        n.copyWith(id: 'n_0002'),
      ),
      isTrue,
    );
    expect(
      await dedup.hasDuplicateNote(
        n.copyWith(id: 'n_0002', text: 'Different'),
      ),
      isFalse,
    );
  });
}
