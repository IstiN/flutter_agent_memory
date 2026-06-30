import '../models/analysis_result.dart';
import '../models/answer.dart';
import '../models/note.dart';
import '../models/question.dart';

/// Removes incomplete entities from an analysis result.
class KBAnalysisValidator {
  void validateAndClean(AnalysisResult analysis) {
    analysis.questions.retainWhere(_isValidQuestion);
    analysis.answers.retainWhere(_isValidAnswer);
    analysis.notes.retainWhere(_isValidNote);
  }

  bool _isValidQuestion(Question q) =>
      _notEmpty(q.author) && _notEmpty(q.date) && _notEmpty(q.area);
  bool _isValidAnswer(Answer a) =>
      _notEmpty(a.author) && _notEmpty(a.date) && _notEmpty(a.area);
  bool _isValidNote(Note n) =>
      _notEmpty(n.author) && _notEmpty(n.date) && _notEmpty(n.area);

  bool _notEmpty(String? value) => value != null && value.trim().isNotEmpty;
}
