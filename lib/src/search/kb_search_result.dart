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
}
