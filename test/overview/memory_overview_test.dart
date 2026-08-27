import 'dart:convert';
import 'dart:io';

import 'package:flutter_agent_memory/src/models/relation.dart';
import 'package:flutter_agent_memory/src/overview/memory_overview.dart';
import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;
  late KBMemoryStore store;
  late String questionId;
  late String answerId;
  late String noteId;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('memory_overview_');
    store = KBMemoryStore.file(tmpDir, source: 'alice');
    final question = await store.addQuestion(
      text: 'How do we deploy the service?',
      area: 'dev',
      tags: ['deploy'],
    );
    final answer = await store.addAnswer(
      text: 'We deploy with GitHub Actions on tag push.',
      area: 'dev',
      tags: ['deploy', 'ci'],
      answersQuestion: question.id,
    );
    final note = await store.addNote(
      text: 'Deploys are frozen during [[${question.id}]] incident review.',
      area: 'dev',
      tags: ['release'],
      importance: 0.9,
      memoryType: 'fact',
      level: 2,
    );
    await store.addRelation(
      note.id,
      answer.id,
      RelationType.supports,
      weight: 0.8,
    );

    questionId = question.id;
    answerId = answer.id;
    noteId = note.id;
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  group('MemoryOverviewService.build', () {
    test('returns records with full metadata', () async {
      final overview = await store.overview();

      expect(overview.records, hasLength(3));
      expect(overview.questionCount, 1);
      expect(overview.answerCount, 1);
      expect(overview.noteCount, 1);

      final note = overview.records.singleWhere((r) => r.id == noteId);
      expect(note.type, 'note');
      expect(note.author, 'agent');
      expect(note.area, 'dev');
      expect(note.importance, 0.9);
      expect(note.memoryType, 'fact');
      expect(note.level, 2);
      expect(note.source, 'alice');
      expect(note.tags, contains('release'));
      expect(note.createdAt, isNotNull);
    });

    test(
      'builds a typed graph from relations, answers, and wiki links',
      () async {
        final overview = await store.overview();
        final edges = overview.graph.edges;

        expect(
          overview.graph.nodes.map((n) => n.id),
          containsAll([questionId, answerId, noteId]),
        );

        // note --supports(0.8)--> answer (explicit relation with weight)
        final supports = edges.singleWhere(
          (e) => e.source == noteId && e.type == RelationType.supports,
        );
        expect(supports.target, answerId);
        expect(supports.weight, 0.8);

        // answer --answers--> question (qa mapping)
        expect(
          edges.any(
            (e) =>
                e.source == answerId &&
                e.target == questionId &&
                e.type == RelationType.answers,
          ),
          isTrue,
        );

        // note --links_to--> question (wiki link in the note text)
        expect(
          edges.any(
            (e) =>
                e.source == noteId &&
                e.target == questionId &&
                e.type == 'links_to',
          ),
          isTrue,
        );
      },
    );

    test('drops edges pointing outside the visible record set', () async {
      // Relation to a non-existent record must not leak into the graph.
      await store.addRelation(noteId, 'n_9999', RelationType.relatedTo);

      final overview = await store.overview();

      expect(overview.graph.edges.where((e) => e.target == 'n_9999'), isEmpty);
    });

    test('area filter scopes records and graph together', () async {
      await store.addNote(text: 'Kitchen fact.', area: 'kitchen');

      final dev = await store.overview(area: 'dev');
      final kitchen = await store.overview(area: 'kitchen');

      expect(dev.records.map((r) => r.area), everyElement('dev'));
      expect(dev.records, hasLength(3));
      expect(kitchen.records, hasLength(1));
      expect(kitchen.graph.nodes, hasLength(1));
    });

    test('tags, author, type, and limit filters apply', () async {
      final ci = await store.overview(tags: ['ci']);
      expect(ci.records.map((r) => r.id), [answerId]);

      final agents = await store.overview(author: 'agent');
      expect(agents.records, hasLength(3));

      final questionsOnly = await store.overview(types: ['question']);
      expect(questionsOnly.records.map((r) => r.id), [questionId]);
      expect(questionsOnly.graph.edges, isEmpty);

      final limited = await store.overview(limit: 1);
      expect(limited.records, hasLength(1));
      expect(limited.graph.nodes, hasLength(1));
    });

    test('empty knowledge base yields an empty overview', () async {
      final emptyDir = Directory.systemTemp.createTempSync('memory_ov_empty_');
      addTearDown(() => emptyDir.deleteSync(recursive: true));
      final emptyStore = KBMemoryStore.file(emptyDir);

      final overview = await emptyStore.overview();

      expect(overview.records, isEmpty);
      expect(overview.graph.nodes, isEmpty);
      expect(overview.graph.edges, isEmpty);
      expect(overview.questionCount, 0);
    });
  });

  group('MemoryOverview serialization', () {
    test('round-trips through toJson/fromJson', () async {
      final overview = await store.overview();
      final restored = MemoryOverview.fromJson(overview.toJson());

      expect(
        restored.records.map((r) => r.id),
        overview.records.map((r) => r.id),
      );
      expect(restored.generatedAt, overview.generatedAt);
      expect(restored.questionCount, overview.questionCount);

      final originalNote = overview.records.singleWhere((r) => r.id == noteId);
      final restoredNote = restored.records.singleWhere((r) => r.id == noteId);
      expect(restoredNote.memoryType, originalNote.memoryType);
      expect(restoredNote.level, originalNote.level);
      expect(restoredNote.tags, originalNote.tags);
      expect(restoredNote.importance, originalNote.importance);

      expect(restored.graph.nodes, hasLength(overview.graph.nodes.length));
      expect(restored.graph.edges, hasLength(overview.graph.edges.length));
      final restoredSupports = restored.graph.edges.singleWhere(
        (e) => e.type == RelationType.supports,
      );
      expect(restoredSupports.weight, 0.8);
    });

    test('is JSON-encodable for transport to a Flutter client', () async {
      final overview = await store.overview();

      final encoded = jsonEncode(overview.toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final restored = MemoryOverview.fromJson(decoded);

      expect(restored.noteCount, 1);
      expect(
        restored.graph.edges.map((e) => e.type),
        containsAll(['supports', 'answers', 'links_to']),
      );
    });

    test('graph nodes carry scope and timestamp metadata', () async {
      final overview = await store.overview();
      final node = overview.graph.nodes.singleWhere((n) => n.id == noteId);

      expect(node.area, 'dev');
      expect(node.importance, 0.9);
      expect(node.level, 2);
      expect(node.createdAt, isNotNull);
      expect(node.tags, contains('release'));
    });
  });
}
