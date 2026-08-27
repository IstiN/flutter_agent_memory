import '../models/answer.dart';
import '../models/note.dart';
import '../models/question.dart';

/// A unified view of a knowledge-base record used by the memory store.
class MemoryRecord {
  final String entityType;
  final String path;
  final Question? question;
  final Answer? answer;
  final Note? note;
  final int accessCount;
  final String? lastAccessedAt;
  final double importance;

  const MemoryRecord({
    required this.entityType,
    required this.path,
    this.question,
    this.answer,
    this.note,
    this.accessCount = 0,
    this.lastAccessedAt,
    this.importance = 0.5,
  });

  String get id => question?.id ?? answer?.id ?? note?.id ?? '';

  String get title => question?.text ?? answer?.text ?? note?.text ?? '';

  String get text => title;

  String get author => question?.author ?? answer?.author ?? note?.author ?? '';

  String get date => question?.date ?? answer?.date ?? note?.date ?? '';

  List<String> get tags =>
      question?.tags ?? answer?.tags ?? note?.tags ?? const [];

  String get area => question?.area ?? answer?.area ?? note?.area ?? '';

  String? get memoryType => note?.memoryType;

  String? get validFrom => note?.validFrom;

  String? get validUntil => note?.validUntil;
}
