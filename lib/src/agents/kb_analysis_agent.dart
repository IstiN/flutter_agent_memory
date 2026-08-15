import 'dart:io';

import '../llm/llm_message.dart';
import '../llm/llm_provider.dart';
import '../models/analysis_result.dart';
import '../models/kb_context.dart';
import '../utils/json_utils.dart';
import '../utils/line_analysis_parser.dart';
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
    _saveRawResponse(response, sourceName);
    final result = _decodeResponse(response, template);
    return result;
  }

  AnalysisResult _decodeResponse(String response, String template) {
    final lineResult = recoverPartialLineAnalysis(response);
    final lineTotal =
        lineResult.questions.length +
        lineResult.answers.length +
        lineResult.notes.length;
    if (lineTotal > 0) {
      return lineResult;
    }

    // Fallback: some models or old test fixtures may still return JSON.
    final trimmed = response.trim();
    if (trimmed.startsWith('{')) {
      try {
        final json = sanitizeAndDecodeJson(response) as Map<String, dynamic>;
        return AnalysisResult.fromJson(json);
      } on FormatException catch (e) {
        _log('JSON fallback decode failed: $e');
        final recovered = recoverPartialAnalysisJson(response);
        final total =
            (recovered['questions'] as List).length +
            (recovered['answers'] as List).length +
            (recovered['notes'] as List).length;
        if (total == 0) rethrow;
        _log('recovered $total items from malformed JSON response');
        return AnalysisResult.fromJson(recovered);
      }
    }

    throw FormatException('Unable to parse analysis response');
  }

  void _saveRawResponse(String response, String sourceName) {
    try {
      final dir = Directory.systemTemp.createTempSync('kb_raw_');
      final file = File('${dir.path}/${sourceName}_raw_response.txt');
      file.writeAsStringSync(response);
      _log('raw response saved to ${file.path}');
    } catch (e) {
      _log('failed to save raw response: $e');
    }
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
