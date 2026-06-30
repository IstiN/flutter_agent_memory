import 'dart:io';

import '../agents/kb_reranker_agent.dart';
import '../agents/kb_tag_generator_agent.dart';
import '../llm/llm_provider.dart';
import '../storage/kb_file_parser.dart';
import '../storage/kb_memory_store.dart' show MemoryRecord;
import 'kb_search_result.dart';
import 'kb_text_search_result.dart';

/// Searches the knowledge base by tags, text, or entity type.
class KBSearchEngine {
  final Directory kbDir;
  final LlmProvider? provider;
  final KBFileParser _parser;

  KBSearchEngine(this.kbDir, {this.provider}) : _parser = KBFileParser();

  /// Returns records whose tags contain all (matchAll=true) or any
  /// (matchAll=false) of the requested tags.
  List<KBSearchResult> searchByTags(
    List<String> tags, {
    bool matchAll = true,
    List<String>? entityTypes,
  }) {
    if (tags.isEmpty) return const [];

    final requested = tags.map((t) => t.toLowerCase()).toSet();
    final types = entityTypes?.map((t) => t.toLowerCase()).toSet() ??
        const {'question', 'answer', 'note'};
    final results = <KBSearchResult>[];

    void scan(String type, String dirName) {
      if (!types.contains(type.toLowerCase())) return;
      _forEachEntityFile(dirName, (file, content) {
        final result = _parseSearchResult(type, file.path, content);
        if (result == null) return;
        final matched = _matchingTags(requested, result.tags, matchAll);
        if (matched == null) return;
        results.add(result.withMatchedTags(matched));
      });
    }

    scan('question', 'questions');
    scan('answer', 'answers');
    scan('note', 'notes');

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
      final accessCount = q?.accessCount ?? a?.accessCount ?? n?.accessCount ?? 0;
      final importance = q?.importance ?? a?.importance ?? n?.importance ?? 0.5;
      final lastUsedDays = daysAgo(q?.lastAccessedAt ?? a?.lastAccessedAt ?? n?.lastAccessedAt);

      double recency = 0;
      if (lastUsedDays <= 1) recency = 10;
      else if (lastUsedDays <= 7) recency = 7;
      else if (lastUsedDays <= 30) recency = 4;
      else if (lastUsedDays <= 90) recency = 2;

      return matchedTags * 10 + keywordScore * 4 + accessCount * 2 + importance * 5 + recency;
    }

    final scored = results.map((r) => (r, score(r))).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((e) => e.$1).toList();
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

    final existingTags = _collectExistingTags();
    final generator = KBTagGeneratorAgent(provider!);
    final generatedTags = await generator.generateTags(
      query,
      existingTags: existingTags,
      maxTags: maxGeneratedTags,
    );

    final tagResults = generatedTags.isEmpty
        ? <KBSearchResult>[]
        : searchByTags(generatedTags, matchAll: matchAll, entityTypes: entityTypes);

    final (keywordResults, keywordHits) = _searchByKeywords(query, entityTypes);
    var merged = _mergeResults(tagResults, keywordResults);
    merged = _rankAndSort(merged, keywordHits: keywordHits);

    if (rerankTopN > 0 && merged.length > 1 && provider != null) {
      final take = merged.length < rerankTopN ? merged.length : rerankTopN;
      final top = merged.sublist(0, take);
      final candidates = top
          .map((r) => MemoryRecord(
                entityType: r.entityType,
                path: r.path,
                question: r.question,
                answer: r.answer,
                note: r.note,
              ))
          .toList();
      final agent = KBRerankerAgent(provider!);
      final rankedIds = await agent.rerank(query, candidates);
      final byId = {for (final r in top) r.id!: r};
      final reranked = rankedIds.map((id) => byId[id]).whereType<KBSearchResult>().toList();
      // Append any remaining results in their original order.
      final rerankedIds = rankedIds.toSet();
      final tail = merged.sublist(take).where((r) => !rerankedIds.contains(r.id)).toList();
      merged = [...reranked, ...tail];
    }

    return KBTextSearchResult(
      generatedTags: generatedTags,
      results: merged,
    );
  }

  /// Collects all unique tags currently used in the knowledge base.
  Set<String> _collectExistingTags() {
    final tags = <String>{};

    void collect(String type, String dirName) {
      _forEachEntityFile(dirName, (_, content) {
        final result = _parseSearchResult(type, '', content);
        if (result != null) tags.addAll(result.tags);
      });
    }

    collect('question', 'questions');
    collect('answer', 'answers');
    collect('note', 'notes');

    return tags.map((t) => t.toLowerCase()).toSet();
  }

  void _forEachEntityFile(String dirName, void Function(File file, String content) action) {
    final dir = Directory('${kbDir.path}/$dirName');
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
      try {
        action(file, file.readAsStringSync());
      } catch (_) {}
    }
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

  List<String>? _matchingTags(Set<String> requested, List<String> recordTags, bool matchAll) {
    final normalized = recordTags.map((t) => t.toLowerCase()).toSet();
    final matched = requested.intersection(normalized).toList();
    if (matched.isEmpty) return null;
    if (matchAll && !requested.every(normalized.contains)) return null;
    return matched;
  }

  /// Tokenizes [query] into searchable keywords and scans record text for hits.
  (List<KBSearchResult>, Map<String, int>) _searchByKeywords(
    String query,
    List<String>? entityTypes,
  ) {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return (<KBSearchResult>[], <String, int>{});

    final types = entityTypes?.map((t) => t.toLowerCase()).toSet() ??
        const {'question', 'answer', 'note'};
    final results = <KBSearchResult>[];
    final hits = <String, int>{};

    void scan(String type, String dirName) {
      if (!types.contains(type.toLowerCase())) return;
      _forEachEntityFile(dirName, (file, content) {
        final result = _parseSearchResult(type, file.path, content);
        if (result == null) return;
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
    }

    scan('question', 'questions');
    scan('answer', 'answers');
    scan('note', 'notes');

    return (results, hits);
  }

  String _recordText(KBSearchResult result) {
    final q = result.question;
    final a = result.answer;
    final n = result.note;
    final title = q?.text ?? a?.text ?? n?.text ?? '';
    final tags = (q?.tags ?? a?.tags ?? n?.tags ?? []).join(' ');
    return '$title $tags';
  }

  List<String> _tokenize(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u00c0-\u017e]+'))
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
