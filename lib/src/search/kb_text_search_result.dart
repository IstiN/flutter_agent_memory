import 'kb_search_result.dart';

/// Result of a natural-language search that uses an LLM to generate tags.
class KBTextSearchResult {
  final List<String> generatedTags;
  final List<KBSearchResult> results;

  /// Non-fatal degradations that happened during the search, e.g. an LLM
  /// stage (tag generation, reranking) timed out and the engine fell back to
  /// keyword-only matching.
  final List<String> warnings;

  const KBTextSearchResult({
    required this.generatedTags,
    required this.results,
    this.warnings = const [],
  });
}
