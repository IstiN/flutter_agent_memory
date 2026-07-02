@TestOn('vm')
@Tags(['integration'])
import 'dart:io';

import 'package:flutter_agent_memory/src/agents/kb_secret_redaction_agent.dart';
import 'package:flutter_agent_memory/src/llm/llm_config.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/llm/provider_factory.dart';
import 'package:flutter_agent_memory/src/models/memory_level.dart';
import 'package:flutter_agent_memory/src/models/memory_type.dart';
import 'package:flutter_agent_memory/src/models/relation.dart';
import 'package:flutter_agent_memory/src/core/kb_orchestrator.dart';
import 'package:flutter_agent_memory/src/core/kb_orchestrator_params.dart';
import 'package:flutter_agent_memory/src/models/kb_processing_mode.dart';
import 'package:flutter_agent_memory/src/search/kb_search_engine.dart';
import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:test/test.dart';

import 'ollama_config.dart';

void main() {
  final config = OllamaConfig.load();
  if (!config.configured) {
    test(
      'skip Ollama integration (not configured)',
      () {},
      skip: 'Ollama not configured',
    );
    return;
  }

  late Directory tmpDir;
  late LlmProvider provider;

  const _projectMeetingTranscript = '''
[2025-06-10T09:00:00Z] Alice: What is the recommended state management approach for the new Flutter app?
[2025-06-10T09:01:00Z] Bob: Use Riverpod. It handles dependency injection and testing well.

[2025-06-10T09:05:00Z] Alice: Should we use BLoC for the checkout flow?
[2025-06-10T09:06:00Z] Charlie: BLoC is overkill there. Riverpod plus AsyncNotifier is enough.

[2025-06-10T09:15:00Z] Alice: How do we run CI/CD for the Flutter project?
[2025-06-10T09:16:00Z] Bob: Use GitHub Actions. Run flutter analyze, flutter test, and flutter build on every pull request.

[2025-06-10T09:25:00Z] Alice: Where should we store API keys?
[2025-06-10T09:26:00Z] Charlie: Use flutter_secure_storage or environment variables. Never commit secrets.

[2025-06-10T09:35:00Z] Alice: How should we structure unit tests?
[2025-06-10T09:36:00Z] Bob: Group related tests, mock dependencies with mocktail, and keep widget tests separate.

[2025-06-10T09:45:00Z] Alice: Do we need a backend service from day one?
[2025-06-10T09:46:00Z] Charlie: Start with Firebase Functions for the MVP. Migrate to a Dart shelf service if traffic grows.

[2025-06-10T09:47:00Z] Alice: Note: API keys must never be committed to the repository.
[2025-06-10T09:55:00Z] Alice: Decision: we will use Riverpod as the primary state management solution.
[2025-06-10T09:56:00Z] Bob: Note: GitHub Actions should run flutter analyze, flutter test, and flutter build on every pull request.
''';

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
    final store = KBMemoryStore.file(
      tmpDir,
      provider: provider,
      source: 'agent',
    );

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

    final marchRecords = await store.list(asOf: DateTime.parse('2025-03-15'));
    expect(marchRecords, hasLength(1));
    expect(marchRecords.first.text, contains('Acme'));

    final mayRecords = await store.list(asOf: DateTime.parse('2025-05-01'));
    expect(mayRecords, hasLength(1));
    expect(mayRecords.first.text, contains('BetaCorp'));
  });

  test('filters notes by memory type', () async {
    final store = KBMemoryStore.file(
      tmpDir,
      provider: provider,
      source: 'agent',
    );

    await store.addNote(
      text: 'Dart is a programming language.',
      memoryType: MemoryType.fact,
    );
    await store.addNote(
      text: 'Team decided to use Riverpod.',
      memoryType: MemoryType.decision,
    );

    final records = await store.list();
    final facts = records
        .where((r) => r.memoryType == MemoryType.fact)
        .toList();
    final decisions = records
        .where((r) => r.memoryType == MemoryType.decision)
        .toList();

    expect(facts, hasLength(1));
    expect(decisions, hasLength(1));
  });

  test('redacts secrets before persisting', () async {
    final store = KBMemoryStore.file(
      tmpDir,
      provider: provider,
      source: 'agent',
    );

    final record = await store.addNote(
      text: 'My API key is sk-12345678901234567890abcdef.',
    );
    final file = File(record.path);
    final content = file.readAsStringSync();

    expect(content, isNot(contains('sk-12345678901234567890abcdef')));
    expect(content, contains(KBSecretRedactionAgent.redacted));
  });

  test('search reranks top candidates', () async {
    final store = KBMemoryStore.file(
      tmpDir,
      provider: provider,
      source: 'agent',
    );
    final engine = KBSearchEngine.file(tmpDir, provider: provider);

    await store.addNote(text: 'How to bake bread.', tags: ['baking']);
    await store.addNote(
      text: 'How to manage state in Flutter using Riverpod.',
      tags: ['flutter', 'state'],
    );
    await store.addNote(
      text: 'Dart async/await patterns.',
      tags: ['dart', 'async'],
    );

    final result = await engine.searchByText(
      'Flutter state management',
      rerankTopN: 2,
    );

    expect(result.results, isNotEmpty);
    // The LLM reranker should put the Flutter/Riverpod note at the top.
    expect(result.results.first.title!.toLowerCase(), contains('flutter'));
  });

  test('persists memory levels and promotes notes', () async {
    final store = KBMemoryStore.file(
      tmpDir,
      provider: provider,
      source: 'agent',
    );

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
    final store = KBMemoryStore.file(
      tmpDir,
      provider: provider,
      source: 'agent',
    );

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

    await store.addRelation(
      source.id,
      target.id,
      RelationType.contradicts,
      weight: 0.9,
    );

    final reloaded = await store.findById(source.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.note!.relations, hasLength(1));

    await store.buildGraph();

    final graphFile = File('${tmpDir.path}/GRAPH.md');
    expect(graphFile.existsSync(), isTrue);

    final content = graphFile.readAsStringSync();
    expect(content, contains('### contradicts'));
    expect(content, contains('[[${source.id}]]'));
    expect(content, contains('[[${target.id}]]'));
  });

  test(
    'rich project meeting transcript yields searchable KB with graph, levels and relations',
    () async {
      final orchestrator = KBOrchestrator(provider);
      final result = await orchestrator.run(
        KBOrchestratorParams(
          sourceName: 'team_meeting_2025_06',
          inputText: _projectMeetingTranscript,
          outputPath: tmpDir.path,
          processingMode: KBProcessingMode.processOnly,
          analysisExtraInstructions:
              'Extract explicit questions, answers and key decisions. Preserve area and 1-3 topics for each record.',
        ),
      );

      expect(result.success, isTrue);
      expect(result.questionsCount, greaterThanOrEqualTo(4));
      expect(result.answersCount, greaterThanOrEqualTo(4));
      expect(result.notesCount, greaterThanOrEqualTo(1));

      // Core output artifacts exist.
      expect(File('${tmpDir.path}/INDEX.md').existsSync(), isTrue);
      expect(
        File('${tmpDir.path}/stats/activity_timeline.md').existsSync(),
        isTrue,
      );
      expect(
        File('${tmpDir.path}/stats/topics_overview.md').existsSync(),
        isTrue,
      );

      final engine = KBSearchEngine.file(tmpDir, provider: provider);

      // Search for state-management recommendation.
      final stateSearch = await engine.searchByText(
        'Which state management should we use in Flutter?',
      );
      expect(stateSearch.results, isNotEmpty);
      expect(stateSearch.generatedTags, isNotEmpty);
      final stateTitles = stateSearch.results
          .map((r) => (r.title ?? '').toLowerCase())
          .toList();
      expect(
        stateTitles.any(
          (t) =>
              t.contains('riverpod') ||
              t.contains('state') ||
              t.contains('bloc'),
        ),
        isTrue,
        reason: 'Expected state-management result, got $stateTitles',
      );

      // Search for CI/CD pipeline.
      final ciSearch = await engine.searchByText(
        'How do we run CI/CD for Flutter?',
      );
      expect(ciSearch.results, isNotEmpty);
      final ciTitles = ciSearch.results
          .map((r) => (r.title ?? '').toLowerCase())
          .toList();
      expect(
        ciTitles.any(
          (t) =>
              t.contains('github') ||
              t.contains('ci') ||
              t.contains('pipeline') ||
              t.contains('action'),
        ),
        isTrue,
        reason: 'Expected CI/CD result, got $ciTitles',
      );

      // Search for API-key security.
      final securitySearch = await engine.searchByText(
        'Where should we store API keys securely?',
      );
      expect(securitySearch.results, isNotEmpty);
      final secTitles = securitySearch.results
          .map((r) => (r.title ?? '').toLowerCase())
          .toList();
      expect(
        secTitles.any(
          (t) =>
              t.contains('secret') ||
              t.contains('secure') ||
              t.contains('key') ||
              t.contains('api'),
        ),
        isTrue,
        reason: 'Expected security result, got $secTitles',
      );

      final store = KBMemoryStore.file(
        tmpDir,
        provider: provider,
        source: 'agent',
      );

      // Notes were extracted from the transcript.
      final notes = await store.list(type: 'note');
      expect(notes, isNotEmpty);

      // Promote the state-management decision note to a concept.
      final decisionNote = notes.firstWhere(
        (n) =>
            n.text.toLowerCase().contains('riverpod') ||
            n.text.toLowerCase().contains('decision'),
        orElse: () => notes.first,
      );
      final promoted = await store.promote(
        decisionNote.id,
        MemoryLevel.concept,
      );
      expect(promoted.note!.level, MemoryLevel.concept);

      // Relate it to a different CI/CD note if one exists.
      final ciNote = notes.firstWhere(
        (n) =>
            n.id != decisionNote.id &&
            (n.text.toLowerCase().contains('github') ||
                n.text.toLowerCase().contains('ci')),
        orElse: () => notes.firstWhere(
          (n) => n.id != decisionNote.id,
          orElse: () => decisionNote,
        ),
      );
      final relationAdded = ciNote.id != decisionNote.id;
      if (relationAdded) {
        await store.addRelation(
          decisionNote.id,
          ciNote.id,
          RelationType.relatedTo,
          weight: 0.8,
        );
      }

      await store.buildGraph();

      final graphFile = File('${tmpDir.path}/GRAPH.md');
      expect(graphFile.existsSync(), isTrue);
      final graphContent = graphFile.readAsStringSync();
      expect(graphContent, contains('id: graph'));
      expect(graphContent, contains('nodes:'));
      expect(graphContent, contains('edges:'));
      expect(graphContent, contains('```mermaid'));

      if (relationAdded) {
        expect(graphContent, contains('### related_to'));
        expect(graphContent, contains('[[${decisionNote.id}]]'));
        expect(graphContent, contains('[[${ciNote.id}]]'));
      }

      // The promoted concept node should be included in the Mermaid diagram.
      final sanitizedDecisionId =
          'n_${decisionNote.id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}_id';
      expect(graphContent, contains('$sanitizedDecisionId['));
    },
    timeout: const Timeout(Duration(seconds: 300)),
  );
}
