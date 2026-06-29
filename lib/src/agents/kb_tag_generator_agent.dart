import 'dart:convert';

import '../llm/llm_provider.dart';

/// Generates a concise set of search tags from a natural-language query.
class KBTagGeneratorAgent {
  final LlmProvider _provider;

  KBTagGeneratorAgent(this._provider);

  /// Returns tags extracted from [query].
  ///
  /// If [existingTags] is provided, the agent is encouraged to reuse them
  /// when they are semantically close to the query.
  Future<List<String>> generateTags(
    String query, {
    Set<String>? existingTags,
    int maxTags = 5,
  }) async {
    final prompt = _buildPrompt(query, existingTags, maxTags);
    final response = await _provider.chat(prompt);
    final jsonText = _extractJson(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    final tags = (json['tags'] as List? ?? []).map((e) => e.toString()).toList();
    return tags.where((t) => t.isNotEmpty).toList();
  }

  String _buildPrompt(String query, Set<String>? existingTags, int maxTags) {
    final existing = existingTags == null || existingTags.isEmpty
        ? '(No existing tag list provided)'
        : existingTags.map((t) => '- $t').join('\n');

    return '''
You are an AI assistant that converts a user's search query into a small set of highly relevant knowledge-base tags.

User query: "$query"

Existing tags in the knowledge base (reuse them when semantically close):
$existing

Return ONLY valid JSON in this exact shape:
{
  "tags": ["tag1", "tag2", ...]
}

Rules:
- Generate between 1 and $maxTags tags.
- Tags should be specific keywords, techniques, tools, or domain terms found in or strongly implied by the query.
- Keep the original language of the query.
- Do not wrap the response in markdown code blocks.
'''.trim();
  }

  String _extractJson(String response) {
    var text = response.trim();
    if (text.startsWith('```json')) {
      text = text.substring(7);
      if (text.endsWith('```')) text = text.substring(0, text.length - 3);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
      if (text.endsWith('```')) text = text.substring(0, text.length - 3);
    }
    return text.trim();
  }
}
