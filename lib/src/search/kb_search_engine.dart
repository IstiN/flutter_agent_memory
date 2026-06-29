import 'dart:io';

import '../agents/kb_tag_generator_agent.dart';
import '../llm/llm_provider.dart';
import '../storage/kb_file_parser.dart';
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
      final dir = Directory('${kbDir.path}/$dirName');
      if (!dir.existsSync()) return;

      for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final content = file.readAsStringSync();
          late final List<String> recordTags;
          KBSearchResult? result;

          switch (type) {
            case 'question':
              final q = _parser.parseQuestion(content);
              recordTags = q.tags;
              result = KBSearchResult(
                path: file.path,
                entityType: 'question',
                question: q,
                matchedTags: const [],
              );
            case 'answer':
              final a = _parser.parseAnswer(content);
              recordTags = a.tags;
              result = KBSearchResult(
                path: file.path,
                entityType: 'answer',
                answer: a,
                matchedTags: const [],
              );
            case 'note':
              final n = _parser.parseNote(content);
              recordTags = n.tags;
              result = KBSearchResult(
                path: file.path,
                entityType: 'note',
                note: n,
                matchedTags: const [],
              );
            default:
              continue;
          }

          final normalized = recordTags.map((t) => t.toLowerCase()).toSet();
          final matched = requested.intersection(normalized).toList();
          if (matched.isEmpty) continue;

          if (matchAll) {
            if (!requested.every(normalized.contains)) continue;
          }

          results.add(KBSearchResult(
            path: result.path,
            entityType: result.entityType,
            question: result.question,
            answer: result.answer,
            note: result.note,
            matchedTags: matched,
          ));
        } catch (_) {
          // Skip malformed files.
        }
      }
    }

    scan('question', 'questions');
    scan('answer', 'answers');
    scan('note', 'notes');

    return _rankAndSort(results);
  }

  /// Ranks results by relevance, access frequency, importance, and recency.
  List<KBSearchResult> _rankAndSort(List<KBSearchResult> results) {
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
      final accessCount = q?.accessCount ?? a?.accessCount ?? n?.accessCount ?? 0;
      final importance = q?.importance ?? a?.importance ?? n?.importance ?? 0.5;
      final lastUsedDays = daysAgo(q?.lastAccessedAt ?? a?.lastAccessedAt ?? n?.lastAccessedAt);

      double recency = 0;
      if (lastUsedDays <= 1) recency = 10;
      else if (lastUsedDays <= 7) recency = 7;
      else if (lastUsedDays <= 30) recency = 4;
      else if (lastUsedDays <= 90) recency = 2;

      return matchedTags * 10 + accessCount * 2 + importance * 5 + recency;
    }

    final scored = results.map((r) => (r, score(r))).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((e) => e.$1).toList();
  }

  /// Generates tags from [query] using the configured LLM provider and then
  /// searches the knowledge base for records that match those tags.
  ///
  /// Throws [StateError] if no [provider] was supplied to the engine.
  Future<KBTextSearchResult> searchByText(
    String query, {
    bool matchAll = false,
    List<String>? entityTypes,
    int maxGeneratedTags = 5,
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

    if (generatedTags.isEmpty) {
      return KBTextSearchResult(generatedTags: generatedTags, results: const []);
    }
    final results = searchByTags(generatedTags, matchAll: matchAll, entityTypes: entityTypes);
    return KBTextSearchResult(generatedTags: generatedTags, results: results);
  }

  /// Collects all unique tags currently used in the knowledge base.
  Set<String> _collectExistingTags() {
    final tags = <String>{};

    void collect(String type, String dirName) {
      final dir = Directory('${kbDir.path}/$dirName');
      if (!dir.existsSync()) return;
      for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final content = file.readAsStringSync();
          switch (type) {
            case 'question':
              tags.addAll(_parser.parseQuestion(content).tags);
            case 'answer':
              tags.addAll(_parser.parseAnswer(content).tags);
            case 'note':
              tags.addAll(_parser.parseNote(content).tags);
          }
        } catch (_) {}
      }
    }

    collect('question', 'questions');
    collect('answer', 'answers');
    collect('note', 'notes');

    return tags.map((t) => t.toLowerCase()).toSet();
  }
}
