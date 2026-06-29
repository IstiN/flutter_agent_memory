import '../models/analysis_result.dart';
import '../models/answer.dart';
import '../models/kb_context.dart';
import '../models/note.dart';
import '../models/question.dart';

/// Maps temporary AI IDs (q_1, a_1, n_1) to permanent IDs (q_0001, ...).
class KBIdMapper {
  AnalysisResult mapAndUpdateIds(AnalysisResult result, KBContext context) {
    final mapping = <String, String>{};

    for (final q in result.questions) {
      mapping[q.id] = 'q_${_pad(context.nextQuestionId())}';
    }
    for (final a in result.answers) {
      mapping[a.id] = 'a_${_pad(context.nextAnswerId())}';
    }
    for (final n in result.notes) {
      mapping[n.id] = 'n_${_pad(context.nextNoteId())}';
    }

    final mappedQuestions = <Question>[];
    for (final q in result.questions) {
      mappedQuestions.add(q.copyWith(
        id: mapping[q.id]!,
        answeredBy: q.answeredBy != null && q.answeredBy!.isNotEmpty
            ? mapping[q.answeredBy]
            : null,
      ));
    }

    final mappedAnswers = <Answer>[];
    for (final a in result.answers) {
      mappedAnswers.add(a.copyWith(
        id: mapping[a.id]!,
        answersQuestion: a.answersQuestion != null && a.answersQuestion!.isNotEmpty
            ? mapping[a.answersQuestion]
            : null,
      ));
    }

    final mappedNotes = <Note>[];
    for (final n in result.notes) {
      mappedNotes.add(n.copyWith(
        id: mapping[n.id]!,
        answersQuestions: n.answersQuestions
            .where((id) => mapping.containsKey(id))
            .map((id) => mapping[id]!)
            .toList(),
      ));
    }

    return AnalysisResult(
      questions: mappedQuestions,
      answers: mappedAnswers,
      notes: mappedNotes,
    );
  }

  String _pad(int value) => value.toString().padLeft(4, '0');
}
