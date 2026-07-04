import '../models/link.dart';

/// Parses a JSON value into a double, tolerating string-encoded numbers.
double doubleFromJson(dynamic value, {double defaultValue = 0.0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return defaultValue;
    return double.tryParse(trimmed) ?? defaultValue;
  }
  return defaultValue;
}

/// Parses a JSON value into an int, tolerating string-encoded numbers.
int intFromJson(dynamic value, {int defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toInt();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return defaultValue;
    return int.tryParse(trimmed) ?? defaultValue;
  }
  return defaultValue;
}

/// Parses a JSON value into a list of strings.
///
/// Tolerant of models that emit a single string or a "[a, b]" literal instead
/// of a real JSON array.
List<String> stringListFromJson(dynamic value) {
  if (value is List) return value.map((e) => e.toString()).toList();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const <String>[];
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      final inner = trimmed.substring(1, trimmed.length - 1).trim();
      if (inner.isEmpty) return const <String>[];
      return inner
          .split(',')
          .map((s) => s.trim().replaceAll(RegExp("^['\"]|[\"']\$"), ''))
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [trimmed];
  }
  return const <String>[];
}

/// Parses a JSON value into a list of [Link]s.
///
/// Tolerant of models that emit plain strings (e.g. answer IDs like "a_1")
/// instead of structured link objects.
List<Link> linkListFromJson(dynamic value) {
  if (value is List) {
    return value.map((e) {
      if (e is Map<String, dynamic>) return Link.fromJson(e);
      if (e is String) return Link(url: e, title: '');
      return Link(url: e.toString(), title: '');
    }).toList();
  }
  return const <Link>[];
}
