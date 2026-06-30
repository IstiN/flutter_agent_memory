import 'dart:convert';

import '../llm/llm_message.dart';
import '../llm/llm_provider.dart';
import '../models/analysis_result.dart';
import '../models/kb_context.dart';
import '../utils/json_utils.dart';

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
    final prompt = _buildPrompt(inputText, context, sourceName, extraInstructions, hasImages: images != null && images.isNotEmpty);
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

  String _buildPrompt(String inputText, KBContext context, String sourceName, String extraInstructions, {bool hasImages = false}) {
    final existingPeople = context.existingPeople.isEmpty
        ? '(No existing people yet)'
        : context.existingPeople.map((p) => '- $p').join('\n');
    final existingTopics = context.existingTopics.isEmpty
        ? '(No existing topics yet)'
        : context.existingTopics.map((t) => '- $t').join('\n');

    final extra = extraInstructions.isEmpty ? '' : '\nAdditional instructions: $extraInstructions\n';
    final imageHint = hasImages
        ? '\nOne or more images are attached. Analyze the text and images together. Extract any questions, answers, or notes visible in the images as well.\n'
        : '';

    return '''
You are an AI assistant specialized in analyzing chat conversations, messages, documentation, and images to extract structured knowledge.
Your task is to identify themes, questions, answers, notes, links and expertise signals from the provided content.
Be thorough and extract ALL valuable information.

Output format: JSON only, no markdown code blocks, no explanatory text.
Use this exact schema:
{
  "questions": [
    {
      "id": "q_1",
      "author": "...",
      "text": "...",
      "date": "YYYY-MM-DDTHH:MM:SSZ",
      "area": "...",
      "topics": ["..."],
      "tags": ["..."],
      "answeredBy": "a_1 or empty string",
      "links": [{"url": "...", "title": "..."}]
    }
  ],
  "answers": [
    {
      "id": "a_1",
      "author": "...",
      "text": "...",
      "date": "YYYY-MM-DDTHH:MM:SSZ",
      "area": "...",
      "topics": ["..."],
      "tags": ["..."],
      "answersQuestion": "q_1 or empty string",
      "quality": 0.0,
      "links": [{"url": "...", "title": "..."}]
    }
  ],
  "notes": [
    {
      "id": "n_1",
      "text": "...",
      "area": "...",
      "topics": ["..."],
      "tags": ["..."],
      "author": "...",
      "date": "YYYY-MM-DDTHH:MM:SSZ",
      "links": [{"url": "...", "title": "..."}]
    }
  ]
}

Rules:
- Temporary IDs: q_1, q_2, a_1, a_2, n_1, n_2, etc. The system will remap them to q_0001, etc.
- Link questions and answers with answeredBy / answersQuestion using the temporary IDs.
- area is required and must be one top-level domain: ai, platform, development, infrastructure, data, security, business, or a specific technology/language (e.g., docker, kubernetes, python).
- topics: 1-3 highly specific themes in the form [service]-[domain]-[aspect], e.g., "github-api-rate-limiting".
- tags: specific techniques/tools/keywords.
- dates must be ISO 8601. Infer from the text if a date is present.
- Quality scores for answers range 0.0-1.0.
- Extract ALL URLs and put them in links.
- For notes, PRESERVE all details; do not summarize.
- Keep the original language of the content.
$imageHint
Existing people:
$existingPeople

Existing topics:
$existingTopics
$extra
Source: $sourceName

Input text:
$inputText
'''.trim();
  }

  String _systemPrompt(KBContext context) {
    return '''
You are a knowledge-base extraction assistant.
Return only valid JSON matching the requested schema.
Be concise but complete.
''';
  }

}
