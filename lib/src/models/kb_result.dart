/// Result of a knowledge-base build operation.
class KBResult {
  final bool success;
  final String message;
  final int questionsCount;
  final int answersCount;
  final int notesCount;
  final int peopleCount;
  final int topicsCount;
  final int areasCount;

  const KBResult({
    required this.success,
    required this.message,
    this.questionsCount = 0,
    this.answersCount = 0,
    this.notesCount = 0,
    this.peopleCount = 0,
    this.topicsCount = 0,
    this.areasCount = 0,
  });

  @override
  String toString() =>
      'KBResult(success: $success, q: $questionsCount, a: $answersCount, n: $notesCount, '
      'people: $peopleCount, topics: $topicsCount, areas: $areasCount)';
}
