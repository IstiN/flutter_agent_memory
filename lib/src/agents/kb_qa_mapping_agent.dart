import 'dart:convert';

import '../llm/llm_provider.dart';
import '../models/analysis_result.dart';
import '../models/kb_context.dart';
import '../models/qa_mapping_result.dart';
import '../utils/json_utils.dart';
import 'prompts/prompt_loader.dart';

/// Maps new answers and notes to existing unanswered questions.
class KBQuestionAnswerMappingAgent {
  final LlmProvider _provider;

  KBQuestionAnswerMappingAgent(this._provider);

  Future<QAMappingResult> mapAnswers(
    AnalysisResult newResult,
    KBContext context, {
    String extraInstructions = '',
  }) async {
    final newAnswers = <_AnswerLike>[];
    for (final a in newResult.answers) {
      newAnswers.add(
        _AnswerLike(
          id: a.id,
          author: a.author,
          text: a.text,
          area: a.area,
          topics: a.topics,
        ),
      );
    }
    for (final n in newResult.notes) {
      newAnswers.add(
        _AnswerLike(
          id: n.id,
          author: n.author,
          text: n.text,
          area: n.area,
          topics: n.topics,
        ),
      );
    }

    final existing = context.existingQuestions
        .where((q) => !q.answered)
        .map(
          (q) => _QuestionLike(
            id: q.id,
            author: q.author,
            text: q.text,
            area: q.area,
          ),
        )
        .toList();

    if (newAnswers.isEmpty || existing.isEmpty) {
      return const QAMappingResult(mappings: []);
    }

    final answersText = newAnswers
        .map((a) {
          return '[${a.id}] by ${a.author}: "${a.text}" (area: ${a.area}, topics: ${a.topics.join(", ")})';
        })
        .join('\n');

    final questionsText = existing
        .map((q) {
          return '[${q.id}] by ${q.author} (UNANSWERED): "${q.text}" (area: ${q.area})';
        })
        .join('\n');

    final prompt = await PromptLoader.load('kb_qa_mapping.xml', {
      'answersText': answersText,
      'questionsText': questionsText,
      'extraInstructions': extraInstructions,
    });
    final response = await _provider.chat(prompt);
    final jsonText = extractJsonFromMarkdown(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    return QAMappingResult.fromJson(json);
  }
}

class _AnswerLike {
  final String id;
  final String author;
  final String text;
  final String area;
  final List<String> topics;

  _AnswerLike({
    required this.id,
    required this.author,
    required this.text,
    required this.area,
    required this.topics,
  });
}

class _QuestionLike {
  final String id;
  final String author;
  final String text;
  final String area;

  _QuestionLike({
    required this.id,
    required this.author,
    required this.text,
    required this.area,
  });
}
