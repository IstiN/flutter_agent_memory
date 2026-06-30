/// A structured result produced by the consolidation agent.
class ConsolidationResult {
  /// High-level Markdown summary of everything the agent remembers.
  final String summary;

  /// Concrete skill cards derived from the memory records.
  final List<SkillCard> skills;

  const ConsolidationResult({
    required this.summary,
    required this.skills,
  });

  factory ConsolidationResult.fromJson(Map<String, dynamic> json) {
    final skillsJson = (json['skills'] as List<dynamic>? ?? []);
    return ConsolidationResult(
      summary: json['summary'] as String? ?? '',
      skills: skillsJson
          .cast<Map<String, dynamic>>()
          .map(SkillCard.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'skills': skills.map((s) => s.toJson()).toList(),
      };
}

/// A single reusable skill extracted from memory.
class SkillCard {
  /// Stable skill id, e.g. "sk_0001".
  final String id;

  /// Short human-readable title.
  final String title;

  /// The actual instruction / know-how.
  final String instruction;

  /// Related tags for discoverability.
  final List<String> tags;

  const SkillCard({
    required this.id,
    required this.title,
    required this.instruction,
    this.tags = const [],
  });

  factory SkillCard.fromJson(Map<String, dynamic> json) {
    return SkillCard(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      instruction: json['instruction'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'instruction': instruction,
        'tags': tags,
      };
}
