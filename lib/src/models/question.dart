import '../utils/model_json_utils.dart';
import 'entity_json_mixin.dart';
import 'link.dart';

/// A knowledge-base question.
class Question with KbEntityJson {
  final String id;
  final String author;
  final String text;
  final String? startTextRef;
  final String? endTextRef;
  final String date;
  final String area;
  final List<String> topics;
  final List<String> tags;
  final String? answeredBy;
  final List<Link> links;
  final int accessCount;
  final String? lastAccessedAt;
  final double importance;

  const Question({
    required this.id,
    required this.author,
    required this.text,
    this.startTextRef,
    this.endTextRef,
    required this.date,
    required this.area,
    required this.topics,
    required this.tags,
    this.answeredBy,
    required this.links,
    this.accessCount = 0,
    this.lastAccessedAt,
    this.importance = 0.5,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
    id: json['id'] as String? ?? '',
    author: json['author'] as String? ?? '',
    text: json['text'] as String? ?? '',
    startTextRef: json['startTextRef'] as String?,
    endTextRef: json['endTextRef'] as String?,
    date: json['date'] as String? ?? '',
    area: json['area'] as String? ?? '',
    topics: stringListFromJson(json['topics']),
    tags: stringListFromJson(json['tags']),
    answeredBy: json['answeredBy'] as String?,
    links: linkListFromJson(json['links']),
    accessCount: intFromJson(json['accessCount'], defaultValue: 0),
    lastAccessedAt: json['lastAccessedAt'] as String?,
    importance: doubleFromJson(json['importance'], defaultValue: 0.5),
  );

  Map<String, dynamic> toJson() => {
    ...toBaseJson(),
    if (answeredBy != null && answeredBy!.isNotEmpty) 'answeredBy': answeredBy,
  };

  Question copyWith({
    String? id,
    String? author,
    String? text,
    String? startTextRef,
    String? endTextRef,
    String? date,
    String? area,
    List<String>? topics,
    List<String>? tags,
    String? answeredBy,
    List<Link>? links,
    int? accessCount,
    String? lastAccessedAt,
    double? importance,
  }) => Question(
    id: id ?? this.id,
    author: author ?? this.author,
    text: text ?? this.text,
    startTextRef: startTextRef ?? this.startTextRef,
    endTextRef: endTextRef ?? this.endTextRef,
    date: date ?? this.date,
    area: area ?? this.area,
    topics: topics ?? this.topics,
    tags: tags ?? this.tags,
    answeredBy: answeredBy ?? this.answeredBy,
    links: links ?? this.links,
    accessCount: accessCount ?? this.accessCount,
    lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    importance: importance ?? this.importance,
  );

  @override
  String toString() => 'Question($id by $author)';
}
