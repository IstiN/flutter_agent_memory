import '../llm/llm_provider.dart';
import '../utils/line_parsers.dart';
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
    _log('generateTags prompt:\n$prompt');
    final response = await _provider.chat(prompt);
    _log('generateTags raw response:\n$response');
    final tags = parseTagGeneratorLines(response);
    _log('generateTags parsed tags: $tags');
    return tags.where((t) => t.isNotEmpty).toList();
  }

  void _log(String message) {
    // ignore: avoid_print
    print('[KBTagGeneratorAgent] $message');
  }
}
