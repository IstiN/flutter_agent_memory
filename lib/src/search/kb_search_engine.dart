import '../agents/kb_reranker_agent.dart';
import '../agents/kb_tag_generator_agent.dart';
import '../llm/llm_provider.dart';
import '../storage/file_kb_storage_factory.dart'
    if (dart.library.html) '../storage/file_kb_storage_factory_stub.dart';
import '../storage/kb_file_parser.dart';
import '../storage/kb_memory_store.dart' show MemoryRecord;
import '../storage/kb_storage.dart';
import 'kb_search_result.dart';
import 'kb_text_search_result.dart';

/// Searches the knowledge base by tags, text, or entity type.
class KBSearchEngine {
  final KbStorage storage;
  final LlmProvider? provider;
  final KBFileParser _parser;

  KBSearchEngine(this.storage, {this.provider}) : _parser = KBFileParser();

  /// Creates a search engine for the classic Markdown file backend.
  factory KBSearchEngine.file(dynamic kbDir, {LlmProvider? provider}) {
    return KBSearchEngine(createFileKbStorage(kbDir), provider: provider);
  }

  /// Returns records whose tags contain all (matchAll=true) or any
  /// (matchAll=false) of the requested tags.
  Future<List<KBSearchResult>> searchByTags(
    List<String> tags, {
    bool matchAll = true,
    List<String>? entityTypes,
  }) async {
    if (tags.isEmpty) return const [];

    final requested = tags.map((t) => t.toLowerCase()).toSet();
    final types =
        entityTypes?.map((t) => t.toLowerCase()).toSet() ??
        const {'question', 'answer', 'note'};
    final results = <KBSearchResult>[];

    await _forEachResult(types, (type, id, content, result) {
      final matched = _matchingTags(requested, result.tags, matchAll);
      if (matched != null) {
        results.add(result.withMatchedTags(matched));
      }
    });

    return _rankAndSort(results);
  }

  /// Ranks results by tag relevance, keyword overlap, access frequency,
  /// importance, and recency.
  List<KBSearchResult> _rankAndSort(
    List<KBSearchResult> results, {
    Map<String, int> keywordHits = const {},
  }) {
    final now = DateTime.now().toUtc();

    int daysAgo(String? iso) {
      if (iso == null || iso.isEmpty) return 365;
      try {
        final dt = DateTime.parse(iso).toUtc();
        return now.difference(dt).inDays;
      } catch (_) {
        return 365;
      }
    }

    double score(KBSearchResult r) {
      final q = r.question;
      final a = r.answer;
      final n = r.note;
      final matchedTags = r.matchedTags.length;
      final keywordScore = keywordHits[r.path] ?? 0;
      final accessCount =
          q?.accessCount ?? a?.accessCount ?? n?.accessCount ?? 0;
      final importance = q?.importance ?? a?.importance ?? n?.importance ?? 0.5;
      final lastUsedDays = daysAgo(
        q?.lastAccessedAt ?? a?.lastAccessedAt ?? n?.lastAccessedAt,
      );

      double recency = 0;
      if (lastUsedDays <= 1)
        recency = 10;
      else if (lastUsedDays <= 7)
        recency = 7;
      else if (lastUsedDays <= 30)
        recency = 4;
      else if (lastUsedDays <= 90)
        recency = 2;

      return matchedTags * 10 +
          keywordScore * 4 +
          accessCount * 2 +
          importance * 5 +
          recency;
    }

    final scored = results.map((r) => (r, score(r))).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((e) => e.$1).toList();
  }

  /// Keyword-only search over record text. Works without an LLM provider —
  /// used as the fallback when [searchByText] cannot generate tags.
  Future<List<KBSearchResult>> searchByKeywords(
    String query, {
    List<String>? entityTypes,
  }) async {
    if (query.trim().isEmpty) return const [];
    final (results, hits) = await _searchByKeywords(query, entityTypes);
    return _rankAndSort(results, keywordHits: hits);
  }

  /// Generates tags from [query] using the configured LLM provider, runs a
  /// tag-based search, and augments it with a keyword search over record text.
  ///
  /// Throws [StateError] if no [provider] was supplied to the engine.
  Future<KBTextSearchResult> searchByText(
    String query, {
    bool matchAll = false,
    List<String>? entityTypes,
    int maxGeneratedTags = 5,
    int rerankTopN = 10,
  }) async {
    if (query.trim().isEmpty) {
      return const KBTextSearchResult(generatedTags: [], results: []);
    }
    if (provider == null) {
      throw StateError(
        'searchByText requires an LLM provider. Pass one to KBSearchEngine constructor.',
      );
    }

    final generatedTags = await _generateTags(query, maxGeneratedTags);
    final tagResults = await _searchByGeneratedTags(
      generatedTags,
      matchAll: matchAll,
      entityTypes: entityTypes,
    );

    final (keywordResults, keywordHits) = await _searchByKeywords(
      query,
      entityTypes,
    );
    var merged = _mergeResults(tagResults, keywordResults);
    merged = _rankAndSort(merged, keywordHits: keywordHits);
    merged = await _rerankIfNeeded(query, merged, rerankTopN);

    return KBTextSearchResult(generatedTags: generatedTags, results: merged);
  }

  Future<List<String>> _generateTags(String query, int maxTags) async {
    final allExistingTags = await _collectExistingTags();
    final relevantTags = _selectRelevantTags(query, allExistingTags, max: 30);
    final generator = KBTagGeneratorAgent(provider!);
    final tags = await generator.generateTags(
      query,
      existingTags: relevantTags,
      maxTags: maxTags,
    );
    // ignore: avoid_print
    print('[KBSearchEngine] searchByText "$query" generated tags: $tags');
    return tags;
  }

  Future<List<KBSearchResult>> _searchByGeneratedTags(
    List<String> generatedTags, {
    required bool matchAll,
    required List<String>? entityTypes,
  }) async {
    if (generatedTags.isEmpty) return const [];
    return searchByTags(
      generatedTags,
      matchAll: matchAll,
      entityTypes: entityTypes,
    );
  }

  Future<List<KBSearchResult>> _rerankIfNeeded(
    String query,
    List<KBSearchResult> merged,
    int rerankTopN,
  ) async {
    if (rerankTopN <= 0 || merged.length <= 1 || provider == null) {
      return merged;
    }

    final take = merged.length < rerankTopN ? merged.length : rerankTopN;
    final top = merged.sublist(0, take);
    final candidates = top
        .map(
          (r) => MemoryRecord(
            entityType: r.entityType,
            path: r.path,
            question: r.question,
            answer: r.answer,
            note: r.note,
          ),
        )
        .toList();
    final agent = KBRerankerAgent(provider!);
    final rankedIds = await agent.rerank(query, candidates);
    final byId = {for (final r in top) r.id!: r};
    final reranked = rankedIds
        .map((id) => byId[id])
        .whereType<KBSearchResult>()
        .toList();
    final rerankedIds = rankedIds.toSet();
    final tail = merged
        .sublist(take)
        .where((r) => !rerankedIds.contains(r.id))
        .toList();
    return [...reranked, ...tail];
  }

  /// Collects all unique tags currently used in the knowledge base.
  Future<Set<String>> _collectExistingTags() async {
    final tags = <String>{};

    Future<void> collect(String type) async {
      await _forEachEntity(type, (_, content) {
        final result = _parseSearchResult(type, '', content);
        if (result != null) tags.addAll(result.tags);
      });
    }

    await collect('question');
    await collect('answer');
    await collect('note');

    return tags.map((t) => t.toLowerCase()).toSet();
  }

  /// Returns a subset of [allTags] that is likely relevant to [query].
  ///
  /// Uses simple substring matching over query words. If too few tags match,
  /// falls back to the full set so the model still has candidates to reuse.
  Set<String> _selectRelevantTags(
    String query,
    Set<String> allTags, {
    int max = 30,
  }) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u00c0-\u017e\u0400-\u04FF]+'))
        .where((t) => t.length > 1)
        .toSet();
    if (words.isEmpty) return allTags;

    final scored = allTags.map((tag) {
      final lower = tag.toLowerCase();
      var score = 0;
      for (final word in words) {
        if (lower.contains(word)) score += 2;
        if (word.contains(lower) && lower.length > 2) score += 1;
      }
      return (tag, score);
    }).toList()..sort((a, b) => b.$2.compareTo(a.$2));

    final relevant = scored
        .where((e) => e.$2 > 0)
        .take(max)
        .map((e) => e.$1)
        .toSet();

    // If almost nothing matches, give the model the full candidate set so it
    // can still reuse broadly related tags.
    if (relevant.length < 5) return allTags;
    return relevant;
  }

  Future<void> _forEachEntity(
    String type,
    void Function(String id, String content) action,
  ) async {
    for (final id in await storage.listEntityIds(type)) {
      try {
        final content = await storage.readEntity(type, id);
        if (content == null) continue;
        action(id, content);
      } catch (_) {}
    }
  }

  Future<void> _forEachResult(
    Set<String> types,
    void Function(String type, String id, String content, KBSearchResult result)
    action,
  ) async {
    Future<void> scan(String type) async {
      if (!types.contains(type.toLowerCase())) return;
      await _forEachEntity(type, (id, content) {
        final result = _parseSearchResult(
          type,
          storage.describeLocation(type, id),
          content,
        );
        if (result == null) return;
        action(type, id, content, result);
      });
    }

    await scan('question');
    await scan('answer');
    await scan('note');
  }

  KBSearchResult? _parseSearchResult(String type, String path, String content) {
    switch (type) {
      case 'question':
        final q = _parser.parseQuestion(content);
        return KBSearchResult(
          path: path,
          entityType: 'question',
          question: q,
          matchedTags: const [],
        );
      case 'answer':
        final a = _parser.parseAnswer(content);
        return KBSearchResult(
          path: path,
          entityType: 'answer',
          answer: a,
          matchedTags: const [],
        );
      case 'note':
        final n = _parser.parseNote(content);
        return KBSearchResult(
          path: path,
          entityType: 'note',
          note: n,
          matchedTags: const [],
        );
    }
    return null;
  }

  List<String>? _matchingTags(
    Set<String> requested,
    List<String> recordTags,
    bool matchAll,
  ) {
    final normalized = recordTags.map((t) => t.toLowerCase()).toSet();
    final matched = requested.intersection(normalized).toList();
    if (matched.isEmpty) return null;
    if (matchAll && !requested.every(normalized.contains)) return null;
    return matched;
  }

  /// Tokenizes [query] into searchable keywords and scans record text for hits.
  Future<(List<KBSearchResult>, Map<String, int>)> _searchByKeywords(
    String query,
    List<String>? entityTypes,
  ) async {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return (<KBSearchResult>[], <String, int>{});

    final types =
        entityTypes?.map((t) => t.toLowerCase()).toSet() ??
        const {'question', 'answer', 'note'};
    final results = <KBSearchResult>[];
    final hits = <String, int>{};

    await _forEachResult(types, (type, id, content, result) {
      final text = _recordText(result).toLowerCase();
      var count = 0;
      for (final token in tokens) {
        if (text.contains(token)) count++;
      }
      if (count > 0) {
        results.add(result);
        hits[result.path] = count;
      }
    });

    return (results, hits);
  }

  String _recordText(KBSearchResult result) {
    final q = result.question;
    final a = result.answer;
    final n = result.note;
    final title = q?.text ?? a?.text ?? n?.text ?? '';
    final startRef =
        q?.startTextRef ?? a?.startTextRef ?? n?.startTextRef ?? '';
    final endRef = q?.endTextRef ?? a?.endTextRef ?? n?.endTextRef ?? '';
    final tags = (q?.tags ?? a?.tags ?? n?.tags ?? []).join(' ');
    final topics = (q?.topics ?? a?.topics ?? n?.topics ?? []).join(' ');
    return '$title $startRef $endRef $tags $topics';
  }

  List<String> _tokenize(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u00c0-\u017e\u0400-\u04FF]+'))
        .where((t) => t.length > 2)
        .toSet()
        .toList();
  }

  List<KBSearchResult> _mergeResults(
    List<KBSearchResult> tagResults,
    List<KBSearchResult> keywordResults,
  ) {
    final byPath = <String, KBSearchResult>{};
    for (final r in tagResults) {
      byPath[r.path] = r;
    }
    for (final r in keywordResults) {
      final existing = byPath[r.path];
      if (existing != null) {
        final mergedTags = {...existing.matchedTags, ...r.matchedTags}.toList();
        byPath[r.path] = existing.withMatchedTags(mergedTags);
      } else {
        byPath[r.path] = r;
      }
    }
    return byPath.values.toList();
  }
}
