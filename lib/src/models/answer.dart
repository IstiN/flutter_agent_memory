import 'link.dart';

/// A knowledge-base answer.
class Answer {
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
        topics: _stringList(json['topics']),
        tags: _stringList(json['tags']),
        answersQuestion: json['answersQuestion'] as String?,
        quality: (json['quality'] as num?)?.toDouble() ?? 0.0,
        links: _linkList(json['links']),
        accessCount: (json['accessCount'] as num?)?.toInt() ?? 0,
        lastAccessedAt: json['lastAccessedAt'] as String?,
        importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'text': text,
        'date': date,
        'area': area,
        'topics': topics,
        'tags': tags,
        if (answersQuestion != null && answersQuestion!.isNotEmpty)
          'answersQuestion': answersQuestion,
        'quality': quality,
        'links': links.map((l) => l.toJson()).toList(),
        'accessCount': accessCount,
        if (lastAccessedAt != null && lastAccessedAt!.isNotEmpty) 'lastAccessedAt': lastAccessedAt,
        'importance': importance,
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

  static List<String> _stringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const <String>[];
  }

  static List<Link> _linkList(dynamic value) {
    if (value is List) return value.map((e) => Link.fromJson(e as Map<String, dynamic>)).toList();
    return const <Link>[];
  }

  @override
  String toString() => 'Answer($id by $author)';
}
