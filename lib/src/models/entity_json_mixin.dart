import 'link.dart';

/// Shared JSON serialization behavior for knowledge-base entities.
///
/// Implementing classes must provide getters for the common fields so that
/// [toBaseJson] can serialize them.
mixin KbEntityJson {
  String get id;
  String get author;
  String get text;
  String get date;
  String get area;
  List<String> get topics;
  List<String> get tags;
  List<Link> get links;
  int get accessCount;
  String? get lastAccessedAt;
  double get importance;

  /// Serializes the fields common to all knowledge-base entities.
  Map<String, dynamic> toBaseJson() => {
        'id': id,
        'author': author,
        'text': text,
        'date': date,
        'area': area,
        'topics': topics,
        'tags': tags,
        'links': links.map((l) => l.toJson()).toList(),
        'accessCount': accessCount,
        if (lastAccessedAt != null && lastAccessedAt!.isNotEmpty) 'lastAccessedAt': lastAccessedAt,
        'importance': importance,
      };
}
