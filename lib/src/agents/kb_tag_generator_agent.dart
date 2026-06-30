import 'dart:convert';

import '../llm/llm_provider.dart';
import '../utils/json_utils.dart';
import 'prompts/prompt_loader.dart';

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
    final existing = existingTags == null || existingTags.isEmpty
        ? '(No existing tag list provided)'
        : existingTags.map((t) => '- $t').join('\n');

    final prompt = await PromptLoader.load('kb_tag_generator.xml', {
      'query': query,
      'existingTags': existing,
      'maxTags': maxTags.toString(),
    });
    final response = await _provider.chat(prompt);
    final jsonText = extractJsonFromMarkdown(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    final tags = (json['tags'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    return tags.where((t) => t.isNotEmpty).toList();
  }
}
