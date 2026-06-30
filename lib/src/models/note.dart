import '../utils/model_json_utils.dart';
import 'entity_json_mixin.dart';
import 'link.dart';

/// A standalone knowledge-base note.
class Note with KbEntityJson {
  final String id;
  final String text;
  final String area;
  final List<String> topics;
  final List<String> tags;
  final String author;
  final String date;
  final List<String> answersQuestions;
  final List<Link> links;
  final int accessCount;
  final String? lastAccessedAt;
  final double importance;

  const Note({
    required this.id,
    required this.text,
    required this.area,
    required this.topics,
    required this.tags,
    required this.author,
    required this.date,
    required this.answersQuestions,
    required this.links,
    this.accessCount = 0,
    this.lastAccessedAt,
    this.importance = 0.5,
  });

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        area: json['area'] as String? ?? '',
        topics: stringListFromJson(json['topics']),
        tags: stringListFromJson(json['tags']),
        author: json['author'] as String? ?? '',
        date: json['date'] as String? ?? '',
        answersQuestions: stringListFromJson(json['answersQuestions']),
        links: linkListFromJson(json['links']),
        accessCount: (json['accessCount'] as num?)?.toInt() ?? 0,
        lastAccessedAt: json['lastAccessedAt'] as String?,
        importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
      );

  Map<String, dynamic> toJson() => {
        ...toBaseJson(),
        if (answersQuestions.isNotEmpty) 'answersQuestions': answersQuestions,
      };

  Note copyWith({
    String? id,
    String? text,
    String? area,
    List<String>? topics,
    List<String>? tags,
    String? author,
    String? date,
    List<String>? answersQuestions,
    List<Link>? links,
    int? accessCount,
    String? lastAccessedAt,
    double? importance,
  }) =>
      Note(
        id: id ?? this.id,
        text: text ?? this.text,
        area: area ?? this.area,
        topics: topics ?? this.topics,
        tags: tags ?? this.tags,
        author: author ?? this.author,
        date: date ?? this.date,
        answersQuestions: answersQuestions ?? this.answersQuestions,
        links: links ?? this.links,
        accessCount: accessCount ?? this.accessCount,
        lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
        importance: importance ?? this.importance,
      );

  @override
  String toString() => 'Note($id by $author)';
}
