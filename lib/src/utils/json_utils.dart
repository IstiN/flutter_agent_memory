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
String repairUnquotedValues(String json) {
  final buffer = StringBuffer();
  var i = 0;
  final length = json.length;

  // Stack of contexts: true = object, false = array.
  final stack = <bool>[];
  // What we expect next: 'key', 'value' or 'none'.
  var expect = 'value';
  var inString = false;

  String escape(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');

  bool isLiteral(String value) {
    final lower = value.toLowerCase();
    return lower == 'true' || lower == 'false' || lower == 'null';
  }

  bool isWhitespace(String ch) =>
      ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

  /// Finds the end of a bare value in an object by looking for the next
  /// `, "key":` delimiter or the closing `}`.
  int findObjectValueEnd(int start) {
    var j = start;
    while (j < length) {
      final c = json[j];
      if (c == '}') return j;
      if (c == ',') {
        var k = j + 1;
        while (k < length && isWhitespace(json[k])) k++;
        if (k < length && json[k] == '"') {
          // skip quoted key
          k++;
          while (k < length) {
            if (json[k] == '\\') {
              k += 2;
            } else if (json[k] == '"') {
              k++;
              break;
            } else {
              k++;
            }
          }
          while (k < length && isWhitespace(json[k])) k++;
          if (k < length && json[k] == ':') return j;
        }
      }
      j++;
    }
    return j;
  }

  /// Finds the end of a bare value in an array by looking for the first
  /// `,` or `]`.
  int findArrayValueEnd(int start) {
    var j = start;
    while (j < length) {
      final c = json[j];
      if (c == ',' || c == ']') return j;
      j++;
    }
    return j;
  }

  /// Finds the end of an unquoted key by looking for `:`.
  int findKeyEnd(int start) {
    var j = start;
    while (j < length) {
      if (json[j] == ':') return j;
      j++;
    }
    return j;
  }

  while (i < length) {
    final ch = json[i];

    if (inString) {
      buffer.write(ch);
      if (ch == '\\') {
        i++;
        if (i < length) buffer.write(json[i]);
      } else if (ch == '"') {
        inString = false;
      }
      i++;
      continue;
    }

    if (ch == '"') {
      buffer.write(ch);
      inString = true;
      i++;
      continue;
    }

    if (ch == '{') {
      stack.add(true);
      expect = 'key';
      buffer.write(ch);
      i++;
      continue;
    }

    if (ch == '[') {
      stack.add(false);
      expect = 'value';
      buffer.write(ch);
      i++;
      continue;
    }

    if (ch == '}') {
      if (stack.isNotEmpty) stack.removeLast();
      expect = 'none';
      buffer.write(ch);
      i++;
      continue;
    }

    if (ch == ']') {
      if (stack.isNotEmpty) stack.removeLast();
      expect = 'none';
      buffer.write(ch);
      i++;
      continue;
    }

    if (ch == ':') {
      expect = 'value';
      buffer.write(ch);
      i++;
      continue;
    }

    if (ch == ',') {
      if (stack.isNotEmpty && stack.last) {
        expect = 'key';
      } else {
        expect = 'value';
      }
      buffer.write(ch);
      i++;
      continue;
    }

    if (isWhitespace(ch)) {
      buffer.write(ch);
      i++;
      continue;
    }

    // Bare token (key or value).
    if (expect == 'key') {
      final end = findKeyEnd(i);
      final key = json.substring(i, end).trim();
      if (key.isNotEmpty) {
        buffer.write('"');
        buffer.write(escape(key));
        buffer.write('"');
      }
      i = end;
    } else if (expect == 'value') {
      final inObject = stack.isNotEmpty && stack.last;
      final end = inObject
          ? findObjectValueEnd(i)
          : stack.isNotEmpty
              ? findArrayValueEnd(i)
              : length;
      final value = json.substring(i, end).trim();
      if (value.isNotEmpty) {
        if (isLiteral(value) || double.tryParse(value) != null) {
          buffer.write(value);
        } else {
          buffer.write('"');
          buffer.write(escape(value));
          buffer.write('"');
        }
      }
      i = end;
    } else {
      // Unexpected bare token outside any context; copy as-is.
      buffer.write(ch);
      i++;
    }
  }

  return buffer.toString();
}

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

    // Detect pattern: newline/comma/whitespace then '{' inside an array
    // when previous non-whitespace was not ',' or '[' or '{' or '}' or ':'
    if (ch == '{') {
      // Look backwards to see if we need a closing brace + comma before this
      var j = buffer.length - 1;
      while (j >= 0 &&
          (buffer.toString()[j] == ' ' ||
              buffer.toString()[j] == '\n' ||
              buffer.toString()[j] == '\r' ||
              buffer.toString()[j] == '\t' ||
              buffer.toString()[j] == ',')) {
        j--;
      }
      final prev = j >= 0 ? buffer.toString()[j] : '';
      // If previous significant char is not array/object opener/comma/colon,
      // we likely have a missing closing brace.
      if (prev.isNotEmpty &&
          prev != '[' &&
          prev != '{' &&
          prev != '}' &&
          prev != ',' &&
          prev != ':') {
        // Insert closing brace before the preceding whitespace/comma
        var insertPos = buffer.length;
        while (insertPos > 0 &&
            (buffer.toString()[insertPos - 1] == ' ' ||
                buffer.toString()[insertPos - 1] == '\n' ||
                buffer.toString()[insertPos - 1] == '\r' ||
                buffer.toString()[insertPos - 1] == '\t')) {
          insertPos--;
        }
        final tail = buffer.toString().substring(insertPos);
        final head = buffer.toString().substring(0, insertPos);
        buffer.clear();
        buffer.write(head);
        buffer.write('},');
        buffer.write(tail);
      }
    }

    buffer.write(ch);
    i++;
  }

  return buffer.toString();
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

    // Opening quote.
    buffer.write(ch);
    i++;
    var inEscape = false;
    while (i < length) {
      final inner = json[i];
      if (inEscape) {
        buffer.write(inner);
        inEscape = false;
        i++;
      } else if (inner == '\\') {
        buffer.write(inner);
        inEscape = true;
        i++;
      } else if (inner == '"') {
        buffer.write(inner);
        i++;
        break;
      } else if (inner == '\n' || inner == '\r') {
        // Unterminated string: close it before the newline.
        buffer.write('"');
        // Leave the newline for the outer loop to process.
        break;
      } else {
        buffer.write(inner);
        i++;
      }
    }
  }

  return buffer.toString();
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
    if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' || ch == ',') {
      i++;
      continue;
    }
    if (ch == ']') break;

    if (ch == '{') {
      final object = _parseBalancedObject(text, i);
      if (object == null) break;
      try {
        final decoded = jsonDecode(sanitizeJson(object)) as Map<String, dynamic>;
        result.add(decoded);
      } catch (_) {
        // One malformed object inside the array: stop this array here.
        break;
      }
      i += object.length;
      continue;
    }

    // Unexpected token inside the array; stop extracting from it.
    break;
  }
  return result;
}

String? _parseBalancedObject(String text, int start) {
  if (start >= text.length || text[start] != '{') return null;
  var depth = 1;
  var inString = false;
  var escape = false;
  for (var i = start + 1; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escape) {
        escape = false;
      } else if (ch == '\\') {
        escape = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
      continue;
    }
    if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
  }
  return null;
}
