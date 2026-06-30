import 'dart:convert';

import '../llm/llm_provider.dart';
import '../storage/kb_memory_store.dart';
import '../utils/json_utils.dart';
import 'prompts/prompt_loader.dart';

/// Reranks a small set of candidate memory records for a given query using an
/// LLM. This is useful when lexical/tag-based scoring is not enough to surface
/// the most relevant record.
class KBRerankerAgent {
  final LlmProvider _provider;

  KBRerankerAgent(this._provider);

  /// Reranks [candidates] for [query].
  ///
  /// Returns the ids in the desired order. Records that the LLM considers
  /// irrelevant may be dropped.
  Future<List<String>> rerank(
    String query,
    List<MemoryRecord> candidates, {
    String extraInstructions = '',
  }) async {
    if (candidates.isEmpty) return const [];
    if (candidates.length == 1) return [candidates.first.id];

    final itemsText = candidates.asMap().entries.map((e) {
      final i = e.key + 1;
      final r = e.value;
      return '$i. [${r.entityType}] ${r.id}: ${r.text}';
    }).join('\n');

    final prompt = await PromptLoader.load('kb_reranker.xml', {
      'query': query,
      'itemsText': itemsText,
      'extraInstructions': extraInstructions,
    });

    final response = await _provider.chat(prompt);
    final jsonText = extractJsonFromMarkdown(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    final ranked = (json['rankedIds'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();

    // Preserve any candidates the model forgot, but at the bottom.
    final seen = <String>{};
    final result = <String>[];
    for (final id in ranked) {
      if (seen.contains(id)) continue;
      if (candidates.any((c) => c.id == id)) {
        result.add(id);
        seen.add(id);
      }
    }
    for (final c in candidates) {
      if (!seen.contains(c.id)) result.add(c.id);
    }
    return result;
  }
}
