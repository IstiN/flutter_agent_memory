import 'dart:convert';

import '../llm/llm_provider.dart';
import '../models/analysis_result.dart';
import '../models/kb_context.dart';
import '../models/qa_mapping_result.dart';

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
      newAnswers.add(_AnswerLike(id: a.id, author: a.author, text: a.text, area: a.area, topics: a.topics));
    }
    for (final n in newResult.notes) {
      newAnswers.add(_AnswerLike(id: n.id, author: n.author, text: n.text, area: n.area, topics: n.topics));
    }

    final existing = context.existingQuestions
        .where((q) => !q.answered)
        .map((q) => _QuestionLike(id: q.id, author: q.author, text: q.text, area: q.area))
        .toList();

    if (newAnswers.isEmpty || existing.isEmpty) {
      return const QAMappingResult(mappings: []);
    }

    final prompt = _buildPrompt(newAnswers, existing, extraInstructions);
    final response = await _provider.chat(prompt);
    final jsonText = _extractJson(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    return QAMappingResult.fromJson(json);
  }

  String _buildPrompt(List<_AnswerLike> newAnswers, List<_QuestionLike> existing, String extraInstructions) {
    final answersText = newAnswers.map((a) {
      return '[${a.id}] by ${a.author}: "${a.text}" (area: ${a.area}, topics: ${a.topics.join(", ")})';
    }).join('\n');

    final questionsText = existing.map((q) {
      return '[${q.id}] by ${q.author} (UNANSWERED): "${q.text}" (area: ${q.area})';
    }).join('\n');

    final extra = extraInstructions.isEmpty ? '' : '\n$extraInstructions\n';

    return '''
You are an AI assistant specialized in matching answers to questions in a knowledge base.

New answers/notes:
$answersText

Existing unanswered questions:
$questionsText
$extra
Return ONLY valid JSON matching this schema:
{
  "mappings": [
    {
      "answerId": "a_1 or n_1",
      "questionId": "q_0001",
      "confidence": 0.9
    }
  ]
}

Rules:
- Only include mappings with confidence >= 0.6.
- Each answer/note maps to AT MOST ONE question.
- A question can have multiple answers.
- Prefer matches within the same area/topic.
- Return an empty mappings array if no good matches exist.
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
