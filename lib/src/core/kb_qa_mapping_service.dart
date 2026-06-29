import '../agents/kb_qa_mapping_agent.dart';
import '../models/analysis_result.dart';
import '../models/kb_context.dart';

/// Applies AI Q&A mapping to an analysis result.
class KBQAMappingService {
  final KBQuestionAnswerMappingAgent _agent;

  KBQAMappingService(this._agent);

  Future<void> applyMapping(
    AnalysisResult analysis,
    KBContext context, {
    String extraInstructions = '',
  }) async {
    if (context.existingQuestions.where((q) => !q.answered).isEmpty) return;

    final result = await _agent.mapAnswers(analysis, context, extraInstructions: extraInstructions);
    final accepted = result.mappings.where((m) => m.confidence >= 0.6).toList();

    for (final mapping in accepted) {
      final answerIndex = analysis.answers.indexWhere((a) => a.id == mapping.answerId);
      if (answerIndex >= 0) {
        analysis.answers[answerIndex] = analysis.answers[answerIndex].copyWith(
          answersQuestion: mapping.questionId,
        );
        continue;
      }

      final noteIndex = analysis.notes.indexWhere((n) => n.id == mapping.answerId);
      if (noteIndex >= 0) {
        final note = analysis.notes[noteIndex];
        if (!note.answersQuestions.contains(mapping.questionId)) {
          analysis.notes[noteIndex] = note.copyWith(
            answersQuestions: [...note.answersQuestions, mapping.questionId],
          );
        }
      }
    }
  }
}
