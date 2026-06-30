import '../llm/llm_provider.dart';
import 'prompts/prompt_loader.dart';

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
    final prompt = await PromptLoader.load('kb_aggregation.xml', {
      'entityType': entityType,
      'entityId': entityId,
      'entityData': entityData,
      'extraInstructions': extraInstructions,
    });
    final response = await _provider.chat(prompt);
    return _stripCodeBlock(response);
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
