/// Hierarchical memory levels inspired by reference frameworks (MemPalace
/// drawers/closets, Mastra observations/reflections, Hindsight mental models).
///
/// Levels are stored as integers so that comparisons and thresholds are easy.
/// Higher levels are more compressed and abstract.
class MemoryLevel {
  static const int raw = 1;
  static const int consolidated = 2;
  static const int concept = 3;

  static const Map<int, String> names = {
    raw: 'raw',
    consolidated: 'consolidated',
    concept: 'concept',
  };

  static int? fromName(String? value) {
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase().trim();
    for (final entry in names.entries) {
      if (entry.value == lower) return entry.key;
    }
    return null;
  }

  static String nameOf(int level) => names[level] ?? 'raw';

  static int normalize(int? level) {
    if (level == null) return raw;
    if (level <= raw) return raw;
    if (level >= concept) return concept;
    return consolidated;
  }
}
