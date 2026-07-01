/// Transforms WebVTT meeting transcripts into clean, LLM-friendly text.
///
/// Mirrors the DMTools VTTUtils behavior:
/// - skips WEBVTT header, empty lines and cue IDs,
/// - extracts speaker names from `<v Speaker>` tags,
/// - keeps simplified timestamps `[HH:MM:SS]`,
/// - groups consecutive lines from the same speaker.
class VttUtils {
  VttUtils._();

  static final RegExp _timestampPattern = RegExp(
    r'(\d{2}:\d{2}:\d{2})\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}',
  );
  static final RegExp _speakerOpenPattern = RegExp(r'<v\s+([^>]+)>');
  static final RegExp _speakerClosePattern = RegExp(r'</v>');
  static final RegExp _cueIdPattern = RegExp(r'^[a-f0-9-]+/\d+-\d+$');

  /// Returns true if [content] looks like a VTT transcript.
  static bool isVttFormat(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('WEBVTT')) return true;
    if (_timestampPattern.hasMatch(content)) return true;
    if (_speakerOpenPattern.hasMatch(content)) return true;
    return false;
  }

  /// Transforms VTT content into clean text with optional [date] header.
  static String transformVtt(String content, {DateTime? date}) {
    if (content.trim().isEmpty) return content;

    final entries = _parseVtt(content);
    if (entries.isEmpty) return content;

    return _formatEntries(entries, date: date);
  }

  static List<_VttEntry> _parseVtt(String content) {
    final entries = <_VttEntry>[];
    String? currentTimestamp;
    final currentText = StringBuffer();
    String? currentSpeaker;
    var insideSpeakerTag = false;

    for (var rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty ||
          line == 'WEBVTT' ||
          _cueIdPattern.hasMatch(line)) {
        continue;
      }

      final tsMatch = _timestampPattern.firstMatch(line);
      if (tsMatch != null) {
        if (currentTimestamp != null &&
            currentSpeaker != null &&
            currentText.isNotEmpty) {
          entries.add(_VttEntry(
            currentTimestamp,
            currentSpeaker,
            currentText.toString().trim(),
          ));
        }
        currentTimestamp = tsMatch.group(1);
        currentText.clear();
        currentSpeaker = null;
        insideSpeakerTag = false;
        continue;
      }

      final openMatch = _speakerOpenPattern.firstMatch(line);
      if (openMatch != null) {
        currentSpeaker = openMatch.group(1)?.trim();
        insideSpeakerTag = true;
        var textAfterTag = line.substring(openMatch.end);

        final closeMatch = _speakerClosePattern.firstMatch(textAfterTag);
        if (closeMatch != null) {
          final text = textAfterTag.substring(0, closeMatch.start).trim();
          if (text.isNotEmpty) {
            _append(currentText, text);
          }
          insideSpeakerTag = false;
        } else {
          final text = textAfterTag.trim();
          if (text.isNotEmpty) {
            _append(currentText, text);
          }
        }
        continue;
      }

      if (insideSpeakerTag) {
        final closeMatch = _speakerClosePattern.firstMatch(line);
        if (closeMatch != null) {
          final text = line.substring(0, closeMatch.start).trim();
          if (text.isNotEmpty) {
            _append(currentText, text);
          }
          insideSpeakerTag = false;
        } else {
          if (line.isNotEmpty) {
            _append(currentText, line);
          }
        }
      }
    }

    if (currentTimestamp != null &&
        currentSpeaker != null &&
        currentText.isNotEmpty) {
      entries.add(_VttEntry(
        currentTimestamp,
        currentSpeaker,
        currentText.toString().trim(),
      ));
    }

    return entries;
  }

  static void _append(StringBuffer buffer, String text) {
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(text);
  }

  static String _formatEntries(
    List<_VttEntry> entries, {
    DateTime? date,
  }) {
    final output = StringBuffer();
    if (date != null) {
      output.writeln('Date: ${date.toIso8601String().substring(0, 10)}');
      output.writeln();
    }

    String? previousSpeaker;
    final currentSpeakerText = StringBuffer();
    String? currentTimestamp;

    void flush() {
      if (previousSpeaker != null && currentSpeakerText.isNotEmpty) {
        output.writeln(
          '[$currentTimestamp] $previousSpeaker: ${currentSpeakerText.toString().trim()}',
        );
      }
    }

    for (final entry in entries) {
      if (entry.speaker == previousSpeaker) {
        currentSpeakerText.write(' ');
        currentSpeakerText.write(entry.text);
      } else {
        flush();
        previousSpeaker = entry.speaker;
        currentTimestamp = entry.timestamp;
        currentSpeakerText.clear();
        currentSpeakerText.write(entry.text);
      }
    }
    flush();

    return output.toString().trim();
  }
}

class _VttEntry {
  final String timestamp;
  final String speaker;
  final String text;

  _VttEntry(this.timestamp, this.speaker, this.text);
}
