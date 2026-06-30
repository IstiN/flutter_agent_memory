/// A typed edge between two memory entities.
///
/// Relations are persisted both inline (in entity frontmatter) and as
/// standalone relation notes in `relations/` for richer metadata.
class Relation {
  final String source;
  final String target;
  final String type;
  final double weight;
  final String? validFrom;
  final String? validUntil;

  const Relation({
    required this.source,
    required this.target,
    required this.type,
    this.weight = 1.0,
    this.validFrom,
    this.validUntil,
  });

  /// Encodes a relation as a compact frontmatter string:
  /// `type|target` or `type|target|weight`.
  String toFrontmatterString() {
    final base = '$type|$target';
    if (weight != 1.0) return '$base|${weight.toStringAsFixed(2)}';
    return base;
  }

  /// Decodes a compact frontmatter string.
  factory Relation.fromFrontmatterString(String source, String value) {
    final parts = value.split('|');
    final rawType = parts.isNotEmpty ? parts[0].trim() : '';
    final type = rawType.isEmpty ? RelationType.relatedTo : rawType;
    final target = parts.length > 1 ? parts[1].trim() : '';
    final weight = parts.length > 2 ? double.tryParse(parts[2].trim()) ?? 1.0 : 1.0;
    return Relation(source: source, target: target, type: type, weight: weight);
  }

  Map<String, dynamic> toJson() => {
        'source': source,
        'target': target,
        'type': type,
        'weight': weight,
        if (validFrom != null) 'validFrom': validFrom,
        if (validUntil != null) 'validUntil': validUntil,
      };

  @override
  String toString() => 'Relation($source -[$type]-> $target)';
}

/// Common relation types borrowed from reference frameworks (CodeGraph,
/// Zep/Graphiti, MemPalace tunnels).
class RelationType {
  static const String answers = 'answers';
  static const String authoredBy = 'authored_by';
  static const String causes = 'causes';
  static const String contradicts = 'contradicts';
  static const String contains = 'contains';
  static const String locatedAt = 'located_at';
  static const String mentions = 'mentions';
  static const String partOf = 'part_of';
  static const String relatedTo = 'related_to';
  static const String sourceOf = 'source_of';
  static const String supports = 'supports';

  static const List<String> values = [
    answers,
    authoredBy,
    causes,
    contradicts,
    contains,
    locatedAt,
    mentions,
    partOf,
    relatedTo,
    sourceOf,
    supports,
  ];

  static String normalize(String? value) {
    final lower = (value ?? '').trim().toLowerCase().replaceAll(' ', '_');
    return values.contains(lower) ? lower : relatedTo;
  }
}
