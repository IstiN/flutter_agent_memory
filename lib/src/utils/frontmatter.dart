import 'dart:collection';

/// Simple YAML-like frontmatter parser/serializer.
///
/// Only supports the inline subset used by this library:
/// strings, numbers, and inline string lists.
class Frontmatter {
  final Map<String, dynamic> _data;

  Frontmatter() : _data = LinkedHashMap<String, dynamic>();

  Frontmatter.from(Map<String, dynamic> data) : _data = LinkedHashMap<String, dynamic>.from(data);

  dynamic operator [](String key) => _data[key];
  void operator []=(String key, dynamic value) => _data[key] = value;

  Map<String, dynamic> get data => Map.unmodifiable(_data);

  List<String> getStringList(String key) {
    final value = _data[key];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        return _parseInlineList(trimmed);
      }
      if (trimmed.isEmpty) return <String>[];
      return <String>[trimmed];
    }
    return <String>[];
  }

  String? getString(String key) {
    final value = _data[key];
    if (value == null) return null;
    return value.toString();
  }

  double? getDouble(String key) {
    final value = _data[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool getBool(String key, {bool defaultValue = false}) {
    final value = _data[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return defaultValue;
  }

  String serialize() {
    final buffer = StringBuffer();
    for (final entry in _data.entries) {
      buffer.write('${entry.key}: ');
      buffer.write(_serializeValue(entry.value));
      buffer.write('\n');
    }
    return buffer.toString();
  }

  static String _serializeValue(dynamic value) {
    if (value is String) {
      return '"${_escape(value)}"';
    } else if (value is List) {
      final items = value.map((e) => '"${_escape(e.toString())}"').join(', ');
      return '[$items]';
    } else {
      return value.toString();
    }
  }

  static String _escape(String value) => value.replaceAll('"', '\\"');
}

/// Parses the first YAML frontmatter block of a Markdown document.
Frontmatter parseFrontmatter(String content) {
  final result = Frontmatter();
  final trimmed = content.trim();
  if (!trimmed.startsWith('---')) return result;

  final endIndex = trimmed.indexOf('---', 3);
  if (endIndex == -1) return result;

  final block = trimmed.substring(3, endIndex).trim();
  for (final line in block.split('\n')) {
    final colonIndex = line.indexOf(':');
    if (colonIndex == -1) continue;
    final key = line.substring(0, colonIndex).trim();
    final rawValue = line.substring(colonIndex + 1).trim();
    result[key] = _parseValue(rawValue);
  }
  return result;
}

String extractBody(String content) {
  final trimmed = content.trim();
  if (!trimmed.startsWith('---')) return trimmed;
  final endIndex = trimmed.indexOf('---', 3);
  if (endIndex == -1) return trimmed;
  return trimmed.substring(endIndex + 3).trim();
}

dynamic _parseValue(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    return _parseInlineList(trimmed);
  }
  if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
    return trimmed.substring(1, trimmed.length - 1).replaceAll('\\"', '"');
  }
  if (trimmed.startsWith("'") && trimmed.endsWith("'") && trimmed.length >= 2) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  if (trimmed == 'true') return true;
  if (trimmed == 'false') return false;
  if (int.tryParse(trimmed) != null) return int.parse(trimmed);
  if (double.tryParse(trimmed) != null) return double.parse(trimmed);
  return trimmed;
}

List<String> _parseInlineList(String raw) {
  final inner = raw.substring(1, raw.length - 1);
  if (inner.trim().isEmpty) return <String>[];
  return inner
      .split(RegExp(r',\s*'))
      .map((s) {
        var value = s.trim();
        if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
          value = value.substring(1, value.length - 1).replaceAll('\\"', '"');
        } else if (value.startsWith("'") && value.endsWith("'") && value.length >= 2) {
          value = value.substring(1, value.length - 1);
        }
        return value;
      })
      .where((s) => s.isNotEmpty)
      .toList();
}
