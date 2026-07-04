/// Shared helpers for plain-text line-oriented LLM output parsers.

/// Parses lines that use ` | ` field separators, e.g. `SKILL | ID=sk_1 | ...`.
///
/// Returns upper-cased field names mapped to their values. The prefix token
/// before the first separator is ignored.
Map<String, String> parsePipeFields(String line) {
  final fields = <String, String>{};
  final parts = line.split(' | ');
  for (final part in parts.skip(1)) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final eqIdx = trimmed.indexOf('=');
    if (eqIdx <= 0) continue;
    final key = trimmed.substring(0, eqIdx).trim().toUpperCase();
    final value = trimmed.substring(eqIdx + 1).trim();
    fields[key] = value;
  }
  return fields;
}

/// Parses a labeled line into a map of upper-case keys to values.
///
/// Splits on " | " first. If that yields no pairs, falls back to splitting on
/// spaces while looking for `KEY=` prefixes.
Map<String, String?> parseLabeledFields(String line) {
  final fields = <String, String?>{};

  // Try the canonical " | " separator first.
  final parts = line.split(' | ');
  for (final part in parts) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final eqIdx = trimmed.indexOf('=');
    if (eqIdx <= 0) continue;
    final key = trimmed.substring(0, eqIdx).trim().toUpperCase();
    final value = trimmed.substring(eqIdx + 1).trim();
    fields[key] = value.isEmpty ? null : value;
  }

  return fields;
}

/// Splits a semicolon-separated string into a list of non-empty trimmed items.
List<String> semicolonList(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  return value.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}
