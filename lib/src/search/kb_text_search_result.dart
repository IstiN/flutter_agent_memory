import 'kb_search_result.dart';

/// Result of a natural-language search that uses an LLM to generate tags.
class KBTextSearchResult {
  final List<String> generatedTags;
  final List<KBSearchResult> results;

  const KBTextSearchResult({
    required this.generatedTags,
    required this.results,
  });
}
