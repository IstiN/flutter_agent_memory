/// Existing knowledge-base state used for incremental updates.
class KBContext {
  final Set<String> existingPeople;
  final Set<String> existingTopics;
  final List<QuestionSummary> existingQuestions;
  int maxQuestionId;
  int maxAnswerId;
  int maxNoteId;

  KBContext({
    Set<String>? existingPeople,
    Set<String>? existingTopics,
    List<QuestionSummary>? existingQuestions,
    this.maxQuestionId = 0,
    this.maxAnswerId = 0,
    this.maxNoteId = 0,
  })  : existingPeople = existingPeople ?? <String>{},
        existingTopics = existingTopics ?? <String>{},
        existingQuestions = existingQuestions ?? <QuestionSummary>[];

  int nextQuestionId() => ++maxQuestionId;
  int nextAnswerId() => ++maxAnswerId;
  int nextNoteId() => ++maxNoteId;
}

class QuestionSummary {
  final String id;
  final String author;
  final String text;
  final String area;
  final bool answered;

  const QuestionSummary({
    required this.id,
    required this.author,
    required this.text,
    required this.area,
    required this.answered,
  });
}
