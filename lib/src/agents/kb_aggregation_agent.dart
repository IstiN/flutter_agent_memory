import '../llm/llm_provider.dart';

/// Generates narrative descriptions for people, topics, and areas.
class KBAggregationAgent {
  final LlmProvider _provider;

  KBAggregationAgent(this._provider);

  Future<String> aggregate(
    String entityType,
    String entityId,
    String entityData, {
    String extraInstructions = '',
  }) async {
    final prompt = _buildPrompt(entityType, entityId, entityData, extraInstructions);
    final response = await _provider.chat(prompt);
    return _stripCodeBlock(response);
  }

  String _buildPrompt(String entityType, String entityId, String entityData, String extraInstructions) {
    final extra = extraInstructions.isEmpty ? '' : '\nAdditional instructions: $extraInstructions\n';

    return '''
You are an AI assistant specialized in writing narrative descriptions for knowledge base entities.

Entity Type: $entityType
Entity ID: $entityId
Entity Data:
$entityData
$extra
Write plain Markdown text (Obsidian-compatible).
- 2-4 paragraphs for people, 1-2 for topics/areas.
- Use [[wiki-links]] for references.
- Be specific and data-driven; avoid generic phrases.
- Do NOT include frontmatter, YAML headers, XML tags, JSON, or code blocks.
'''.trim();
  }

  String _stripCodeBlock(String response) {
    var text = response.trim();
    if (text.startsWith('```')) {
      final end = text.lastIndexOf('```');
      if (end > 3) text = text.substring(text.indexOf('\n') + 1, end);
    }
    return text.trim();
  }
}
