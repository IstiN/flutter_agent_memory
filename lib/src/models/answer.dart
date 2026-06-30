import '../utils/model_json_utils.dart';
import 'entity_json_mixin.dart';
import 'link.dart';

/// A knowledge-base answer.
class Answer with KbEntityJson {
  final String id;
  final String author;
  final String text;
  final String date;
  final String area;
  final List<String> topics;
  final List<String> tags;
  final String? answersQuestion;
  final double quality;
  final List<Link> links;
  final int accessCount;
  final String? lastAccessedAt;
  final double importance;

  const Answer({
    required this.id,
    required this.author,
    required this.text,
    required this.date,
    required this.area,
    required this.topics,
    required this.tags,
    this.answersQuestion,
    this.quality = 0.0,
    required this.links,
    this.accessCount = 0,
    this.lastAccessedAt,
    this.importance = 0.5,
  });

  factory Answer.fromJson(Map<String, dynamic> json) => Answer(
        id: json['id'] as String? ?? '',
        author: json['author'] as String? ?? '',
        text: json['text'] as String? ?? '',
        date: json['date'] as String? ?? '',
        area: json['area'] as String? ?? '',
        topics: stringListFromJson(json['topics']),
        tags: stringListFromJson(json['tags']),
        answersQuestion: json['answersQuestion'] as String?,
        quality: (json['quality'] as num?)?.toDouble() ?? 0.0,
        links: linkListFromJson(json['links']),
        accessCount: (json['accessCount'] as num?)?.toInt() ?? 0,
        lastAccessedAt: json['lastAccessedAt'] as String?,
        importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
      );

  Map<String, dynamic> toJson() => {
        ...toBaseJson(),
        if (answersQuestion != null && answersQuestion!.isNotEmpty)
          'answersQuestion': answersQuestion,
        'quality': quality,
      };

  Answer copyWith({
    String? id,
    String? author,
    String? text,
    String? date,
    String? area,
    List<String>? topics,
    List<String>? tags,
    String? answersQuestion,
    double? quality,
    List<Link>? links,
    int? accessCount,
    String? lastAccessedAt,
    double? importance,
  }) =>
      Answer(
        id: id ?? this.id,
        author: author ?? this.author,
        text: text ?? this.text,
        date: date ?? this.date,
        area: area ?? this.area,
        topics: topics ?? this.topics,
        tags: tags ?? this.tags,
        answersQuestion: answersQuestion ?? this.answersQuestion,
        quality: quality ?? this.quality,
        links: links ?? this.links,
        accessCount: accessCount ?? this.accessCount,
        lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
        importance: importance ?? this.importance,
      );

  @override
  String toString() => 'Answer($id by $author)';
}
