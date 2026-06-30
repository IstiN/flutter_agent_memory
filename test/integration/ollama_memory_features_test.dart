@TestOn('vm')
import 'dart:io';

import 'package:flutter_agent_memory/src/agents/kb_secret_redaction_agent.dart';
import 'package:flutter_agent_memory/src/llm/llm_config.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/llm/provider_factory.dart';
import 'package:flutter_agent_memory/src/models/memory_level.dart';
import 'package:flutter_agent_memory/src/models/memory_type.dart';
import 'package:flutter_agent_memory/src/models/relation.dart';
import 'package:flutter_agent_memory/src/search/kb_search_engine.dart';
import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:test/test.dart';

import 'ollama_config.dart';

void main() {
  final config = OllamaConfig.load();
  if (!config.configured) {
    test('skip Ollama integration (not configured)', () {}, skip: 'Ollama not configured');
    return;
  }

  late Directory tmpDir;
  late LlmProvider provider;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('fam_memory_features_');
    provider = ProviderFactory.create(
      LlmConfig(
        providerName: 'openai',
        apiKey: config.apiKey,
        baseUrl: config.baseUrl,
        model: config.model,
      ),
    );
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('adds fact note with validity and filters by as-of date', () async {
    final store = KBMemoryStore(tmpDir, provider: provider, source: 'agent');

    await store.addNote(
      text: 'Alice worked at Acme from January to March 2025.',
      memoryType: MemoryType.fact,
      validFrom: '2025-01-01T00:00:00Z',
      validUntil: '2025-03-31T23:59:59Z',
    );

    await store.addNote(
      text: 'Alice joined BetaCorp in April 2025.',
      memoryType: MemoryType.fact,
      validFrom: '2025-04-01T00:00:00Z',
    );

    final marchRecords = store.list(asOf: DateTime.parse('2025-03-15'));
    expect(marchRecords, hasLength(1));
    expect(marchRecords.first.text, contains('Acme'));

    final mayRecords = store.list(asOf: DateTime.parse('2025-05-01'));
    expect(mayRecords, hasLength(1));
    expect(mayRecords.first.text, contains('BetaCorp'));
  });

  test('filters notes by memory type', () async {
    final store = KBMemoryStore(tmpDir, provider: provider, source: 'agent');

    await store.addNote(text: 'Dart is a programming language.', memoryType: MemoryType.fact);
    await store.addNote(text: 'Team decided to use Riverpod.', memoryType: MemoryType.decision);

    final facts = store.list().where((r) => r.memoryType == MemoryType.fact).toList();
    final decisions = store.list().where((r) => r.memoryType == MemoryType.decision).toList();

    expect(facts, hasLength(1));
    expect(decisions, hasLength(1));
  });

  test('redacts secrets before persisting', () async {
    final store = KBMemoryStore(tmpDir, provider: provider, source: 'agent');

    final record = await store.addNote(text: 'My API key is sk-12345678901234567890abcdef.');
    final file = File(record.path);
    final content = file.readAsStringSync();

    expect(content, isNot(contains('sk-12345678901234567890abcdef')));
    expect(content, contains(KBSecretRedactionAgent.redacted));
  });

  test('search reranks top candidates', () async {
    final store = KBMemoryStore(tmpDir, provider: provider, source: 'agent');
    final engine = KBSearchEngine(tmpDir, provider: provider);

    await store.addNote(text: 'How to bake bread.', tags: ['baking']);
    await store.addNote(text: 'How to manage state in Flutter using Riverpod.', tags: ['flutter', 'state']);
    await store.addNote(text: 'Dart async/await patterns.', tags: ['dart', 'async']);

    final result = await engine.searchByText(
      'Flutter state management',
      rerankTopN: 2,
    );

    expect(result.results, isNotEmpty);
    // The LLM reranker should put the Flutter/Riverpod note at the top.
    expect(result.results.first.title!.toLowerCase(), contains('flutter'));
  });

  test('persists memory levels and promotes notes', () async {
    final store = KBMemoryStore(tmpDir, provider: provider, source: 'agent');

    final note = await store.addNote(
      text: 'Flutter state management patterns.',
      memoryType: MemoryType.observation,
      level: MemoryLevel.raw,
    );

    // Raw level is the default and is omitted from frontmatter.
    final file = File(note.path);
    expect(note.note!.level, MemoryLevel.raw);
    expect(file.readAsStringSync(), isNot(contains('level:')));

    final promoted = await store.promote(note.id, MemoryLevel.concept);
    expect(promoted.note!.level, MemoryLevel.concept);
    expect(File(promoted.path).readAsStringSync(), contains('level: 3'));
  });

  test('relations and graph survive a round-trip through the store', () async {
    final store = KBMemoryStore(tmpDir, provider: provider, source: 'agent');

    final source = await store.addNote(
      text: 'Prefer Riverpod over Provider.',
      memoryType: MemoryType.decision,
      level: MemoryLevel.consolidated,
    );
    final target = await store.addNote(
      text: 'Provider is simpler for small apps.',
      memoryType: MemoryType.fact,
      level: MemoryLevel.raw,
    );

    await store.addRelation(source.id, target.id, RelationType.contradicts, weight: 0.9);

    final reloaded = store.findById(source.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.note!.relations, hasLength(1));

    store.buildGraph();

    final graphFile = File('${tmpDir.path}/GRAPH.md');
    expect(graphFile.existsSync(), isTrue);

    final content = graphFile.readAsStringSync();
    expect(content, contains('### contradicts'));
    expect(content, contains('[[${source.id}]]'));
    expect(content, contains('[[${target.id}]]'));
  });
}
