@TestOn('vm')
import 'dart:io';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:flutter_agent_memory/src/models/memory_level.dart';
import 'package:flutter_agent_memory/src/models/relation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Deterministic LLM provider used only to exercise text search across adapters.
class _KeywordProvider implements LlmProvider {
  @override
  String get defaultModel => 'fake';

  @override
  Future<String> chat(String prompt, {String? model}) async {
    final lower = prompt.toLowerCase();
    if (lower.contains('state') || lower.contains('riverpod')) {
      return '{"tags": ["riverpod", "state-management", "flutter"]}';
    }
    if (lower.contains('ci') ||
        lower.contains('github') ||
        lower.contains('deploy')) {
      return '{"tags": ["ci-cd", "github-actions", "flutter"]}';
    }
    return '{"tags": ["dart"]}';
  }

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) =>
      chat(messages.first.content);
}

class _StorageFixture {
  final KbStorage storage;
  final Directory? directory;

  _StorageFixture(this.storage, {this.directory});
}

void main() {
  final fixtures = <String, _StorageFixture Function()>{
    'in-memory': () => _StorageFixture(InMemoryKbStorage()),
    'sqlite': () => _StorageFixture(SqliteKbStorage(sqlite3.openInMemory())),
    'file': () {
      final dir = Directory.systemTemp.createTempSync('kb_adapter_int_');
      return _StorageFixture(FileKbStorage(dir), directory: dir);
    },
  };

  for (final entry in fixtures.entries) {
    group('KBMemoryStore + KBSearchEngine over ${entry.key}', () {
      late _StorageFixture fixture;
      late KbStorage storage;

      setUp(() {
        fixture = entry.value();
        storage = fixture.storage;
      });

      tearDown(() {
        final dir = fixture.directory;
        if (dir != null && dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      test('builds, searches and graphs realistic knowledge base', () async {
        final store = KBMemoryStore(storage, source: 'agent');

        final stateQuestion = await store.addQuestion(
          text:
              'What is the recommended state management approach for a new Flutter app?',
          area: 'development',
          tags: ['flutter', 'state'],
        );
        final stateAnswer = await store.addAnswer(
          text:
              'Use Riverpod. It handles dependency injection and testing well.',
          area: 'development',
          tags: ['riverpod'],
          answersQuestion: stateQuestion.id,
        );
        final stateNote = await store.addNote(
          text:
              'Riverpod AsyncNotifier is a good fit for async state. See also [[${stateQuestion.id}]].',
          area: 'development',
          tags: ['riverpod', 'async'],
          level: MemoryLevel.concept,
        );
        final ciQuestion = await store.addQuestion(
          text: 'How do we run CI/CD for the Flutter project?',
          area: 'infrastructure',
          tags: ['ci-cd', 'github-actions'],
        );

        await store.addRelation(
          stateNote.id,
          stateQuestion.id,
          RelationType.relatedTo,
          weight: 0.8,
        );

        // Round-trip checks.
        final reloaded = await store.findById(stateQuestion.id);
        expect(reloaded, isNotNull);
        expect(reloaded!.question, isNotNull);
        expect(reloaded.tags, contains('#question'));
        expect(reloaded.tags, contains('#source_agent'));

        final riverpodRecords = await store.list(tags: ['riverpod']);
        expect(
          riverpodRecords.map((r) => r.id).toSet(),
          containsAll({stateAnswer.id, stateNote.id}),
        );

        // Graph generation with typed edges and wiki-links.
        await store.buildGraph();
        final graph = await storage.readFile('GRAPH.md');
        expect(graph, isNotNull);
        expect(graph, contains('id: graph'));
        expect(graph, contains('[[${stateQuestion.id}]]'));
        expect(graph, contains('[[${stateAnswer.id}]]'));
        expect(graph, contains('[[${stateNote.id}]]'));
        expect(graph, contains('### answers'));
        expect(graph, contains('### related_to'));
        // The wiki-link duplicates the explicit related_to relation, so it is
        // folded into the typed edge and no generic links_to section remains.
        expect(graph, isNot(contains('### links_to')));
        // Concept-level notes are included in the Mermaid diagram.
        final sanitizedNoteId =
            'n_${stateNote.id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}_id';
        expect(graph, contains('$sanitizedNoteId['));

        // Tag-based search works across all backends.
        final engine = KBSearchEngine(storage);
        final tagResults = await engine.searchByTags([
          'riverpod',
        ], matchAll: false);
        final ids = tagResults.map((r) => r.id).toSet();
        expect(ids, containsAll({stateAnswer.id, stateNote.id}));
        expect(ids, isNot(contains(ciQuestion.id)));

        // Text search delegates tag generation to the provider and returns results.
        final textEngine = KBSearchEngine(
          storage,
          provider: _KeywordProvider(),
        );
        final textResults = await textEngine.searchByText(
          'Flutter state management',
        );
        expect(textResults.results, isNotEmpty);
        expect(
          textResults.results.map((r) => r.id).toSet(),
          contains(stateAnswer.id),
        );
      });
    });
  }
}
