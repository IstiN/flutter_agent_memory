import 'dart:convert';

/// Extracts a JSON string that may be wrapped in markdown code fences or
/// preceded by thinking tags such as `<think>...</think>`.
String extractJsonFromMarkdown(String response) {
  var text = response.trim();

  // Strip reasoning/thinking blocks produced by models like Qwen3/DeepSeek.
  text = text.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();

  if (text.startsWith('```json')) {
    text = text.substring(7);
    if (text.endsWith('```')) text = text.substring(0, text.length - 3);
  } else if (text.startsWith('```')) {
    text = text.substring(3);
    if (text.endsWith('```')) text = text.substring(0, text.length - 3);
  }
  return text.trim();
}

/// Removes trailing commas before `]` or `}`.
///
/// Small local models often emit trailing commas inside arrays/objects, which
/// are not valid JSON. This lightweight repair lets the rest of the pipeline
/// consume their output without failing.
String repairTrailingCommas(String json) {
  return json
      .replaceAllMapped(RegExp(r',(\s*[}\]])'), (match) => match.group(1)!);
}

/// Quotes bare scalar values that appear after object keys or inside arrays.
///
/// Local models often emit unquoted strings as values, e.g.
/// `"text": Docker image for Dart backend: ...` or `[Flutter, Dart]`. This
/// repair quotes such values so the resulting text is valid JSON. It skips
/// values that are already quoted, numbers, booleans, null, arrays or objects.
String repairUnquotedValues(String json) =>
    _UnquotedValueRepairer(json).repair();

class _UnquotedValueRepairer {
  final String json;
  final StringBuffer buffer = StringBuffer();
  final List<bool> stack = <bool>[];
  var expect = 'value';
  var inString = false;
  var i = 0;

  _UnquotedValueRepairer(this.json);

  String repair() {
    while (i < json.length) {
      _processChar(json[i]);
    }
    return buffer.toString();
  }

  static final _structuralHandlers =
      <String, void Function(_UnquotedValueRepairer, String)>{
        '"': (r, ch) => r._startString(ch),
        '{': (r, _) => r._open(true, 'key'),
        '[': (r, _) => r._open(false, 'value'),
        '}': (r, ch) => r._close(ch),
        ']': (r, ch) => r._close(ch),
        ':': (r, ch) => r._setExpect('value', ch),
        ',': (r, ch) => r._comma(ch),
      };

  void _processChar(String ch) {
    if (inString) {
      _handleInString(ch);
      return;
    }
    final handler = _structuralHandlers[ch];
    if (handler != null) {
      handler(this, ch);
      return;
    }
    if (_isJsonWhitespace(ch)) {
      _copy(ch);
    } else {
      _bareToken(ch);
    }
  }

  void _handleInString(String ch) {
    buffer.write(ch);
    if (ch == '\\') {
      i++;
      if (i < json.length) buffer.write(json[i]);
    } else if (ch == '"') {
      inString = false;
    }
    i++;
  }

  void _startString(String ch) {
    buffer.write(ch);
    inString = true;
    i++;
  }

  void _open(bool isObject, String nextExpect) {
    stack.add(isObject);
    expect = nextExpect;
    buffer.write(isObject ? '{' : '[');
    i++;
  }

  void _close(String ch) {
    if (stack.isNotEmpty) stack.removeLast();
    expect = 'none';
    buffer.write(ch);
    i++;
  }

  void _setExpect(String value, String ch) {
    expect = value;
    buffer.write(ch);
    i++;
  }

  void _comma(String ch) {
    expect = (stack.isNotEmpty && stack.last) ? 'key' : 'value';
    buffer.write(ch);
    i++;
  }

  void _copy(String ch) {
    buffer.write(ch);
    i++;
  }

  void _bareToken(String ch) {
    if (expect == 'key') {
      _quoteKey();
    } else if (expect == 'value') {
      _quoteValue();
    } else {
      buffer.write(ch);
      i++;
    }
  }

  void _quoteKey() {
    final end = _findKeyEnd(i);
    final key = json.substring(i, end).trim();
    if (key.isNotEmpty) {
      buffer.write('"${_escapeJsonString(key)}"');
    }
    i = end;
  }

  void _quoteValue() {
    final end = _valueEnd();
    final value = json.substring(i, end).trim();
    if (value.isNotEmpty) {
      if (_isJsonLiteral(value) || double.tryParse(value) != null) {
        buffer.write(value);
      } else {
        buffer.write('"${_escapeJsonString(value)}"');
      }
    }
    i = end;
  }

  int _valueEnd() {
    if (stack.isEmpty) return json.length;
    return stack.last ? _findObjectValueEnd(i) : _findArrayValueEnd(i);
  }

  int _findKeyEnd(int start) {
    var j = start;
    while (j < json.length && json[j] != ':') j++;
    return j;
  }

  int _findArrayValueEnd(int start) {
    var j = start;
    while (j < json.length) {
      final c = json[j];
      if (c == ',' || c == ']') return j;
      j++;
    }
    return j;
  }

  int _findObjectValueEnd(int start) {
    var j = start;
    while (j < json.length) {
      final c = json[j];
      if (c == '}') return j;
      if (c == ',' && _followedByQuotedKey(j)) return j;
      j++;
    }
    return j;
  }

  bool _followedByQuotedKey(int commaIndex) {
    var k = _skipWhitespace(commaIndex + 1);
    if (k >= json.length || json[k] != '"') return false;
    k = _skipQuotedString(k + 1);
    k = _skipWhitespace(k);
    return k < json.length && json[k] == ':';
  }

  int _skipWhitespace(int start) {
    var k = start;
    while (k < json.length && _isJsonWhitespace(json[k])) k++;
    return k;
  }

  int _skipQuotedString(int start) {
    var k = start;
    while (k < json.length) {
      if (json[k] == '\\') {
        k += 2;
      } else if (json[k] == '"') {
        return k + 1;
      } else {
        k++;
      }
    }
    return k;
  }
}

String _escapeJsonString(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\r')
    .replaceAll('\t', '\\t');

bool _isJsonLiteral(String value) {
  final lower = value.toLowerCase();
  return lower == 'true' || lower == 'false' || lower == 'null';
}

bool _isJsonWhitespace(String ch) =>
    ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

/// Repairs objects in arrays where the closing brace and following comma
/// are missing because the model continued with the next array element.
///
/// Example:
///   "date": "202025-1116"
///   ,
///   {
/// becomes:
///   "date": "202025-1116"
///   },
///   {
String repairBrokenArrayObjects(String json) {
  final buffer = StringBuffer();
  var i = 0;
  final length = json.length;

  while (i < length) {
    final ch = json[i];
    if (ch == '{' && _needsClosingBrace(buffer)) {
      _insertClosingBrace(buffer);
    }
    buffer.write(ch);
    i++;
  }

  return buffer.toString();
}

bool _isWhitespaceOrComma(String ch) =>
    ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' || ch == ',';

bool _isStructuralOrComma(String ch) =>
    ch == '[' || ch == '{' || ch == '}' || ch == ',' || ch == ':';

bool _needsClosingBrace(StringBuffer buffer) {
  final prev = _previousSignificantChar(buffer);
  return prev.isNotEmpty && !_isStructuralOrComma(prev);
}

String _previousSignificantChar(StringBuffer buffer) {
  final text = buffer.toString();
  var j = text.length - 1;
  while (j >= 0 && _isWhitespaceOrComma(text[j])) {
    j--;
  }
  return j >= 0 ? text[j] : '';
}

void _insertClosingBrace(StringBuffer buffer) {
  final text = buffer.toString();
  var insertPos = text.length;
  while (insertPos > 0 && _isJsonWhitespace(text[insertPos - 1])) {
    insertPos--;
  }
  buffer
    ..clear()
    ..write(text.substring(0, insertPos))
    ..write('},')
    ..write(text.substring(insertPos));
}

/// Repairs unterminated string values that reach the end of an object/array
/// element before a closing quote.
///
/// Example:
///   "answeredBy": "Uladzimir Klyshevich
///   }
/// becomes:
///   "answeredBy": "Uladzimir Klyshevich"
///   }
String repairUnterminatedStringValues(String json) {
  final buffer = StringBuffer();
  var i = 0;
  final length = json.length;

  while (i < length) {
    final ch = json[i];

    if (ch != '"') {
      buffer.write(ch);
      i++;
      continue;
    }

    i = _copyQuotedString(json, buffer, i);
  }

  return buffer.toString();
}

int _copyQuotedString(String json, StringBuffer buffer, int start) {
  var i = start;
  // Opening quote.
  buffer.write(json[i]);
  i++;
  var inEscape = false;
  while (i < json.length) {
    final inner = json[i];
    if (inEscape) {
      buffer.write(inner);
      inEscape = false;
      i++;
      continue;
    }
    if (inner == '\\') {
      buffer.write(inner);
      inEscape = true;
      i++;
      continue;
    }
    if (inner == '"') {
      buffer.write(inner);
      return i + 1;
    }
    if (inner == '\n' || inner == '\r') {
      // Unterminated string: close it before the newline.
      buffer.write('"');
      // Leave the newline for the outer loop to process.
      return i;
    }
    buffer.write(inner);
    i++;
  }
  return i;
}

/// Repairs keys where the colon between key and value is missing.
///
/// Gemma sometimes emits quoted keys with a trailing space and no colon,
/// followed by a bare value, e.g.:
///   "author "Uladzimir Klyshevich",
///   "text "I don't need IDE."
String repairMissingColonsAfterKeys(String json) {
  return json
      .replaceAllMapped(
        RegExp(r'"author\s*"\s*([^:\s,}"][^,}"]*)"?'),
        (m) => '"author": "${m.group(1)}"',
      )
      .replaceAllMapped(
        RegExp(r'"text\s*"\s*([^:\s,}"][^,}"]*)"?'),
        (m) => '"text": "${m.group(1)}"',
      )
      .replaceAllMapped(
        RegExp(r'"id\s*"\s*([^:\s,}"][^,}"]*)"?'),
        (m) => '"id": "${m.group(1)}"',
      )
      .replaceAllMapped(
        RegExp(r'"date\s*"\s*([^:\s,}"][^,}"]*)"?'),
        (m) => '"date": "${m.group(1)}"',
      )
      .replaceAllMapped(
        RegExp(r'"answeredBy\s*"\s*([^:\s,}"][^,}"]*)"?'),
        (m) => '"answeredBy": "${m.group(1)}"',
      )
      .replaceAllMapped(
        RegExp(r'"answersQuestion\s*"\s*([^:\s,}"][^,}"]*)"?'),
        (m) => '"answersQuestion": "${m.group(1)}"',
      )
      .replaceAllMapped(
        RegExp(r'"quality\s*"\s*([^:\s,}"][^,}"]*)"?'),
        (m) => '"quality": ${m.group(1)}',
      );
}

/// Repairs corrupted keys produced by local models.
String repairCorruptedKeys(String json) {
  return json
      .replaceAllMapped(
        RegExp(r'(^|\s)"?\s*per\s*"\s*:'),
        (m) => '${m.group(1)}"text":',
      )
      .replaceAllMapped(
        RegExp(r'"\s*(tex|texr|text|teext)\s*"\s*:'),
        (_) => '"text":',
      );
}

/// Repairs dates emitted by local models into valid ISO 8601 strings.
///
/// Accepts messy values like "202310-27T0500Z", "2023-10-27T0500Z",
/// "202310-7T00Z", "202310-7000" and normalizes them to a placeholder
/// ISO 8601 date when they cannot be parsed precisely.
/// Repairs dates emitted by local models into valid ISO 8601 strings.
///
/// Accepts messy values like "202310-27T0500Z", "2023-10-27T0500Z",
/// "202310-7T00Z", "202310-7000" and normalizes them to a placeholder
/// ISO 8601 date when they cannot be parsed precisely.
String repairMalformedDates(String json) {
  var result = json;

  // Gemma often emits YYYYMM-DDTHHMMZ (e.g. "202310-27T0500Z").
  result = result.replaceAllMapped(
    RegExp(r'"(\d{4})(\d{2})-(\d{1,2})T(\d{2})(\d{2})Z"'),
    (m) {
      final year = m.group(1)!;
      final month = m.group(2)!.padLeft(2, '0');
      final day = m.group(3)!.padLeft(2, '0');
      final hour = m.group(4)!.padLeft(2, '0');
      final minute = m.group(5)!.padLeft(2, '0');
      return '"$year-$month-${day}T$hour:$minute:00Z"';
    },
  );

  // Gemma sometimes drops the "T" and "Z": "202310-7T00Z", "202310-7000".
  result = result.replaceAllMapped(
    RegExp(r'"(\d{4})(\d{2})-(\d{1,2})(?:T?(\d{0,2})(\d{0,2})(\d{0,2})Z?)"'),
    (m) {
      final year = m.group(1)!;
      final month = m.group(2)!.padLeft(2, '0');
      final day = m.group(3)!.padLeft(2, '0');
      final hour = m.group(4)!.padLeft(2, '0');
      final minute = m.group(5)!.padLeft(2, '0');
      final second = m.group(6)!.padLeft(2, '0');
      return '"$year-$month-${day}T$hour:$minute:${second}Z"';
    },
  );

  // General fallback for other messy dates.
  result = result.replaceAllMapped(
    RegExp(
      r'"(\d{4,6})[-]?(\d{1,2})[-]?(\d{1,2})[T\s]?(\d{0,2}):?(\d{0,2}):?(\d{0,2})Z?"',
    ),
    (match) {
      final yearStr = match.group(1)!;
      final monthStr = match.group(2)!;
      final dayStr = match.group(3)!;
      final hourStr = match.group(4)!.padLeft(2, '0');
      final minuteStr = match.group(5)!.padLeft(2, '0');
      final secondStr = match.group(6)!.padLeft(2, '0');

      var year = int.tryParse(yearStr) ?? 2000;
      if (yearStr.length == 6) {
        // Gemma sometimes emits "202310" meaning 2023-10.
        year = int.tryParse(yearStr.substring(0, 4)) ?? 2000;
      }
      final month = int.tryParse(monthStr) ?? 1;
      final day = int.tryParse(dayStr) ?? 1;

      final clampedYear = year.clamp(0, 9999).toString().padLeft(4, '0');
      final clampedMonth = month.clamp(1, 12).toString().padLeft(2, '0');
      final clampedDay = day.clamp(1, 31).toString().padLeft(2, '0');

      return '"$clampedYear-$clampedMonth-${clampedDay}T$hourStr:$minuteStr:${secondStr}Z"';
    },
  );

  return result;
}

/// Removes ASCII control characters (except tab, newline and carriage return)
/// that some models inject into otherwise valid JSON.
String stripControlCharacters(String json) {
  return json.replaceAll(RegExp(r'[\x00-\x08\x0B-\x0C\x0E-\x1F]'), '');
}

/// Repairs common local-model JSON malformations.
///
/// Applies, in order:
/// 1. Markdown/thinking block stripping
/// 2. Control character removal
/// 3. Repair of missing colons after quoted keys
/// 4. Repair of corrupted keys
/// 5. Repair of unterminated string values
/// 6. Repair of broken array objects (missing closing brace)
/// 7. Repair of malformed dates
/// 8. Trailing comma removal
/// 9. Quoting of bare string values
String sanitizeJson(String response) {
  var jsonText = extractJsonFromMarkdown(response);
  jsonText = stripControlCharacters(jsonText);
  jsonText = repairMissingColonsAfterKeys(jsonText);
  jsonText = repairCorruptedKeys(jsonText);
  jsonText = repairUnterminatedStringValues(jsonText);
  jsonText = repairBrokenArrayObjects(jsonText);
  jsonText = repairMalformedDates(jsonText);
  jsonText = repairTrailingCommas(jsonText);
  jsonText = repairUnquotedValues(jsonText);
  return jsonText;
}

/// Parses a model response that may contain malformed JSON into a Dart object.
dynamic sanitizeAndDecodeJson(String response) {
  final jsonText = sanitizeJson(response);
  return jsonDecode(jsonText);
}

/// Extracts as many complete objects as possible from a broken analysis JSON.
///
/// Local models sometimes "go off the rails" mid-response (repeated digits,
/// mixed languages, random symbols). This recovery scans each expected array
/// (`questions`, `answers`, `notes`) and pulls out every object whose braces
/// are balanced, then tries to sanitize + decode that object individually.
/// The result is a map that [AnalysisResult.fromJson] can consume, so a single
/// corrupted chunk does not kill the whole transcript.
Map<String, dynamic> recoverPartialAnalysisJson(String response) {
  final jsonText = sanitizeJson(response);
  return {
    'questions': _extractArrayObjects(jsonText, 'questions'),
    'answers': _extractArrayObjects(jsonText, 'answers'),
    'notes': _extractArrayObjects(jsonText, 'notes'),
  };
}

List<Map<String, dynamic>> _extractArrayObjects(String text, String key) {
  final result = <Map<String, dynamic>>[];
  final pattern = RegExp('"$key"\\s*:\\s*\\[');
  final match = pattern.firstMatch(text);
  if (match == null) return result;

  var i = match.end;
  final length = text.length;
  while (i < length) {
    final ch = text[i];
    if (_isArraySeparator(ch)) {
      i++;
      continue;
    }
    if (ch == ']') break;

    final advance = _tryExtractObject(text, i, result);
    if (advance == null) break;
    i += advance;
  }
  return result;
}

int? _tryExtractObject(
  String text,
  int start,
  List<Map<String, dynamic>> result,
) {
  if (text[start] != '{') return null;
  final object = _parseBalancedObject(text, start);
  if (object == null) return null;
  final decoded = _tryDecodeObject(object);
  if (decoded == null) return null;
  result.add(decoded);
  return object.length;
}

bool _isArraySeparator(String ch) =>
    ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' || ch == ',';

Map<String, dynamic>? _tryDecodeObject(String object) {
  try {
    return jsonDecode(sanitizeJson(object)) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

String? _parseBalancedObject(String text, int start) {
  if (start >= text.length || text[start] != '{') return null;
  return _BalancedObjectParser(text, start).parse();
}

class _BalancedObjectParser {
  final String text;
  final int start;
  var depth = 1;
  var inString = false;
  var escape = false;

  _BalancedObjectParser(this.text, this.start);

  String? parse() {
    for (var i = start + 1; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        _handleInString(ch);
      } else {
        final done = _handleOutOfString(ch, i);
        if (done) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  void _handleInString(String ch) {
    if (escape) {
      escape = false;
    } else if (ch == '\\') {
      escape = true;
    } else if (ch == '"') {
      inString = false;
    }
  }

  bool _handleOutOfString(String ch, int index) {
    if (ch == '"') {
      inString = true;
      return false;
    }
    if (ch == '{') {
      depth++;
      return false;
    }
    if (ch == '}') {
      depth--;
      return depth == 0;
    }
    return false;
  }
}
