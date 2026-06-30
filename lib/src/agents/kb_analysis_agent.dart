import 'dart:convert';

import '../llm/llm_message.dart';
import '../llm/llm_provider.dart';
import '../models/analysis_result.dart';
import '../models/kb_context.dart';
import '../utils/json_utils.dart';
import 'prompts/prompt_loader.dart';

/// Extracts structured knowledge (questions, answers, notes) from raw text
/// and optionally images.
class KBAnalysisAgent {
  final LlmProvider _provider;

  KBAnalysisAgent(this._provider);

  Future<AnalysisResult> analyze(
    String inputText,
    KBContext context, {
    String sourceName = 'unknown',
    String extraInstructions = '',
    List<String>? images,
  }) async {
    final prompt = await _buildPrompt(
      inputText,
      context,
      sourceName,
      extraInstructions,
      hasImages: images != null && images.isNotEmpty,
    );
    final response = images != null && images.isNotEmpty
        ? await _provider.chatMessages([
            LlmMessage(role: 'system', content: _systemPrompt(context)),
            LlmMessage(role: 'user', content: prompt, images: images),
          ])
        : await _provider.chat(prompt);
    final jsonText = extractJsonFromMarkdown(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    return AnalysisResult.fromJson(json);
  }

  Future<String> _buildPrompt(
    String inputText,
    KBContext context,
    String sourceName,
    String extraInstructions, {
    bool hasImages = false,
  }) async {
    final existingPeople = context.existingPeople.isEmpty
        ? '(No existing people yet)'
        : context.existingPeople.map((p) => '- $p').join('\n');
    final existingTopics = context.existingTopics.isEmpty
        ? '(No existing topics yet)'
        : context.existingTopics.map((t) => '- $t').join('\n');

    final imageHint = hasImages
        ? 'One or more images are attached. Analyze the text and images together. Extract any questions, answers, or notes visible in the images as well.'
        : '';

    return PromptLoader.load('kb_analysis.xml', {
      'inputText': inputText,
      'sourceName': sourceName,
      'existingPeople': existingPeople,
      'existingTopics': existingTopics,
      'imageHint': imageHint,
      'extraInstructions': extraInstructions,
    });
  }

  String _systemPrompt(KBContext context) {
    return '''
You are a knowledge-base extraction assistant.
Return only valid JSON matching the requested schema.
Be concise but complete.
'''
        .trim();
  }
}
