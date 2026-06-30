/// Constants for categorizing notes inside the knowledge base.
///
/// These types are intentionally scoped to [Note] entities. Questions and
/// answers keep their own semantics; most durable memories from reference
/// systems (facts, events, observations, beliefs, etc.) map naturally to a
/// note with a specific memory type.
class MemoryType {
  static const String fact = 'fact';
  static const String event = 'event';
  static const String observation = 'observation';
  static const String belief = 'belief';
  static const String decision = 'decision';
  static const String rule = 'rule';
  static const String experience = 'experience';
  static const String generic = 'generic';

  static const List<String> values = [
    fact,
    event,
    observation,
    belief,
    decision,
    rule,
    experience,
    generic,
  ];

  static String? normalize(String? value) {
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase().trim();
    return values.contains(lower) ? lower : generic;
  }
}
