import '../models/answer.dart';
import '../models/note.dart';
import '../models/question.dart';

/// Result of a knowledge-base search.
class KBSearchResult {
  final String path;
  final String entityType;
  final Question? question;
  final Answer? answer;
  final Note? note;
  final List<String> matchedTags;

  const KBSearchResult({
    required this.path,
    required this.entityType,
    this.question,
    this.answer,
    this.note,
    required this.matchedTags,
  });

  String? get id {
    return question?.id ?? answer?.id ?? note?.id;
  }

  String? get title {
    return question?.text ?? answer?.text ?? note?.text;
  }

  @override
  String toString() => 'KBSearchResult($entityType: $id, tags: $matchedTags)';

  /// Convenience helper for creating a copy with updated matched tags.
  KBSearchResult withMatchedTags(List<String> tags) => KBSearchResult(
    path: path,
    entityType: entityType,
    question: question,
    answer: answer,
    note: note,
    matchedTags: tags,
  );

  /// All tags of the underlying entity.
  List<String> get tags =>
      question?.tags ?? answer?.tags ?? note?.tags ?? const [];
}
