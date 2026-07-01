import 'dart:io';

import 'package:flutter_agent_memory/src/models/memory_level.dart';
import 'package:flutter_agent_memory/src/models/relation.dart';
import 'package:flutter_agent_memory/src/storage/kb_graph_builder.dart';
import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;
  late KBMemoryStore store;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('kb_graph_');
    store = KBMemoryStore.file(tmpDir, source: 'agent');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('GRAPH.md is generated with nodes, edges and mermaid block', () async {
    await store.addQuestion(
      text: 'What is Dart?',
      area: 'development',
      tags: ['dart'],
    );
    await store.addAnswer(
      text: 'Dart is a programming language.',
      area: 'development',
      tags: ['dart'],
      answersQuestion: 'q_0001',
    );
    await store.addNote(
      text: 'Use strong mode.',
      area: 'development',
      tags: ['dart'],
      answersQuestions: ['q_0001'],
    );

    await KBGraphBuilder.file(tmpDir).build();

    final graphFile = File('${tmpDir.path}/GRAPH.md');
    expect(graphFile.existsSync(), isTrue);
    final content = graphFile.readAsStringSync();

    expect(content, contains('id: graph'));
    expect(content, contains('nodes:'));
    expect(content, contains('edges:'));
    expect(content, contains('```mermaid'));
    expect(content, contains('graph TD;'));
    expect(content, contains('## Typed Relations'));

    // Edges: answer -> question and note -> question.
    expect(content, contains('[[a_0001]]'));
    expect(content, contains('[[q_0001]]'));
    expect(content, contains('[[n_0001]]'));
  });

  test('explicit relations are rendered as typed edges', () async {
    final source = await store.addNote(
      text: 'Source note',
      area: 'dev',
      tags: ['x'],
    );
    final target = await store.addNote(
      text: 'Target note',
      area: 'dev',
      tags: ['y'],
    );

    await store.addRelation(
      source.id,
      target.id,
      RelationType.supports,
      weight: 2.0,
    );

    await KBGraphBuilder.file(tmpDir).build();

    final content = File('${tmpDir.path}/GRAPH.md').readAsStringSync();
    expect(content, contains('### supports'));
    expect(content, contains('[[${source.id}]]'));
    expect(content, contains('[[${target.id}]]'));
  });

  test('wiki-links are discovered as edges', () async {
    final target = await store.addNote(
      text: 'Target',
      area: 'dev',
      tags: ['x'],
    );
    await store.addNote(
      text: 'See also [[${target.id}]].',
      area: 'dev',
      tags: ['x'],
    );

    await KBGraphBuilder.file(tmpDir).build();

    final content = File('${tmpDir.path}/GRAPH.md').readAsStringSync();
    expect(content, contains('### links_to'));
  });

  test('high-level nodes are preferred when the diagram is truncated', () async {
    await store.addNote(
      text: 'Low level raw note.',
      area: 'dev',
      tags: ['x'],
      level: MemoryLevel.raw,
    );
    await store.addNote(
      text: 'High level concept note.',
      area: 'dev',
      tags: ['x'],
      level: MemoryLevel.concept,
    );

    // Force truncation (total nodes = 4, limit = 3) so the preference logic
    // is exercised. Small graphs show everything by default.
    await KBGraphBuilder.file(tmpDir).build(maxMermaidNodes: 3);

    final content = File('${tmpDir.path}/GRAPH.md').readAsStringSync();
    // The concept-level note should be included in the mermaid diagram.
    expect(content, contains('n_n_0002_id["High level concept note."]'));
    // The raw note is below the threshold and should be omitted.
    expect(content, isNot(contains('n_n_0001_id')));
  });
}
