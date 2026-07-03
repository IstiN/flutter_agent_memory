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
    String template = 'kb_analysis.xml',
  }) async {
    final prompt = await _buildPrompt(
      inputText,
      context,
      sourceName,
      extraInstructions,
      template: template,
      hasImages: images != null && images.isNotEmpty,
    );
    _log('analyze prompt length=${prompt.length}');
    _log('analyze prompt:\n$prompt');
    final response = await _provider.chatMessages([
      LlmMessage(role: 'user', content: prompt, images: images),
    ]);
    _log('analyze raw response length=${response.length}');
    _log('analyze raw response:\n$response');
    final jsonText = extractJsonFromMarkdown(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    return AnalysisResult.fromJson(json);
  }

  void _log(String message) {
    // ignore: avoid_print
    print('[KBAnalysisAgent] $message');
  }

  Future<String> _buildPrompt(
    String inputText,
    KBContext context,
    String sourceName,
    String extraInstructions, {
    bool hasImages = false,
    required String template,
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

    return PromptLoader.load(template, {
      'inputText': inputText,
      'sourceName': sourceName,
      'existingPeople': existingPeople,
      'existingTopics': existingTopics,
      'imageHint': imageHint,
      'extraInstructions': extraInstructions,
    });
  }

}
