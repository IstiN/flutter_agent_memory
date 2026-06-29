import 'answer.dart';
import 'note.dart';
import 'question.dart';

/// Raw extraction result returned by the analysis agent.
class AnalysisResult {
  final List<Question> questions;
  final List<Answer> answers;
  final List<Note> notes;

  const AnalysisResult({
    required this.questions,
    required this.answers,
    required this.notes,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) => AnalysisResult(
        questions: (json['questions'] as List? ?? [])
            .map((e) => Question.fromJson(e as Map<String, dynamic>))
            .toList(),
        answers: (json['answers'] as List? ?? [])
            .map((e) => Answer.fromJson(e as Map<String, dynamic>))
            .toList(),
        notes: (json['notes'] as List? ?? [])
            .map((e) => Note.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'questions': questions.map((q) => q.toJson()).toList(),
        'answers': answers.map((a) => a.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
      };

  AnalysisResult copyWith({
    List<Question>? questions,
    List<Answer>? answers,
    List<Note>? notes,
  }) =>
      AnalysisResult(
        questions: questions ?? this.questions,
        answers: answers ?? this.answers,
        notes: notes ?? this.notes,
      );

  @override
  String toString() =>
      'AnalysisResult(questions: ${questions.length}, answers: ${answers.length}, notes: ${notes.length})';
}
