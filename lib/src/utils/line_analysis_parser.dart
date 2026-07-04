import '../models/analysis_result.dart';
import '../models/answer.dart';
import '../models/link.dart';
import '../models/note.dart';
import '../models/question.dart';
import 'line_parser_utils.dart';

/// Parses the labeled line-oriented analysis format.
///
/// One record per line. Fields are `KEY=value` pairs separated by
/// " | ". Lists (TOPICS, TAGS) use ';' inside the value.
///
/// Example:
/// ```
/// TYPE=Q | ID=q_1 | AUTHOR=Alice | DATE=2024-11-15T09:00:00Z | AREA=development | TOPICS=dart-state-management | TAGS=dart;testing | ANSWERED_BY=a_1 | START=full | END=full
/// TYPE=A | ID=a_1 | AUTHOR=Bob | DATE=2024-11-15T09:01:00Z | AREA=development | TOPICS=dart-state-management | TAGS=riverpod | ANSWERS_QUESTION=q_1 | QUALITY=0.8 | START=full | END=full
/// ```
AnalysisResult parseLineAnalysisFormat(String response) {
  final questions = <Question>[];
  final answers = <Answer>[];
  final notes = <Note>[];

  // Strip XML-like artifacts the model sometimes echoes from the prompt.
  final cleanedResponse = response
      .replaceAll('</raw_input>', '')
      .replaceAll(RegExp(r'</output\b[^>]*>'), '')
      .replaceAll('</output_format>', '')
      .replaceAll('</format>', '')
      .replaceAll('<output>', '')
      .replaceAll('</prompt>', '')
      .replaceAll(RegExp(r'</(?:answer|question|note)\b[^>]*>'), '')
      .replaceAll(RegExp(r'<(?:output|answer|question|note)>'), '');

  // Split records by TYPE= boundaries. Models sometimes emit multiple records
  // on a single line, so a newline-only split is not enough. A real record
  // boundary is TYPE=<letter> preceded by start-of-string, whitespace, or " | ".
  // We split on all TYPE= starts and then keep only Q/A/N records.
  final typeMatches = RegExp(r'TYPE=[A-Za-z]\b').allMatches(cleanedResponse);
  final starts = <int>[];
  for (final m in typeMatches) {
    if (m.start == 0) {
      starts.add(0);
    } else {
      final before = cleanedResponse[m.start - 1];
      if (before == '|' || before.trim().isEmpty) {
        starts.add(m.start);
      }
    }
  }

  for (var i = 0; i < starts.length; i++) {
    final start = starts[i];
    final end = i + 1 < starts.length ? starts[i + 1] : cleanedResponse.length;
    final record = cleanedResponse.substring(start, end).trim();
    if (record.isEmpty) continue;
    if (!record.startsWith(RegExp(r'TYPE=[QAN]\b'))) continue;

    final fields = parseLabeledFields(record);
    final type = fields['TYPE'] ?? '';
    final id = fields['ID'] ?? '';
    if (id.isEmpty) continue;

    final author = fields['AUTHOR'] ?? '';
    final date = fields['DATE'] ?? '';
    final area = fields['AREA'] ?? 'general';
    final topics = semicolonList(fields['TOPICS']);
    final tags = semicolonList(fields['TAGS']);
    final links = _parseLinks(fields['LINKS']);
    final startRef = fields['START'];
    final endRef = fields['END'];

    switch (type) {
      case 'Q':
        questions.add(
          Question(
            id: id,
            author: author,
            text: '',
            startTextRef: startRef,
            endTextRef: endRef,
            date: date,
            area: area,
            topics: topics,
            tags: tags,
            answeredBy: _normalizeEmpty(fields['ANSWERED_BY']),
            links: links,
          ),
        );
      case 'A':
        answers.add(
          Answer(
            id: id,
            author: author,
            text: '',
            startTextRef: startRef,
            endTextRef: endRef,
            date: date,
            area: area,
            topics: topics,
            tags: tags,
            answersQuestion: _normalizeEmpty(fields['ANSWERS_QUESTION']),
            quality: _parseDouble(fields['QUALITY']),
            links: links,
          ),
        );
      case 'N':
        notes.add(
          Note(
            id: id,
            text: '',
            startTextRef: startRef,
            endTextRef: endRef,
            area: area,
            topics: topics,
            tags: tags,
            author: author,
            date: date,
            answersQuestions: const [],
            links: links,
            memoryType: fields['MEMORY_TYPE'],
          ),
        );
    }
  }

  return AnalysisResult(
    questions: questions,
    answers: answers,
    notes: notes,
  );
}

double _parseDouble(String? value) {
  if (value == null || value.trim().isEmpty) return 0.0;
  return double.tryParse(value.trim()) ?? 0.0;
}

List<Link> _parseLinks(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  return value
      .split(';')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && _looksLikeUrl(s))
      .map((url) => Link(url: url, title: url))
      .toList();
}

bool _looksLikeUrl(String value) {
  final lower = value.toLowerCase();
  return lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('ftp://') ||
      lower.startsWith('file://') ||
      RegExp(r'^[a-zA-Z0-9-]+://').hasMatch(value);
}

String? _normalizeEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (lower == '(empty)' ||
      lower == 'empty' ||
      lower == 'none' ||
      lower == 'n/a' ||
      lower == 'null') {
    return null;
  }
  return trimmed;
}

/// Recovers as many valid records as possible from a malformed response.
AnalysisResult recoverPartialLineAnalysis(String response) {
  // The parser already skips malformed lines, so a direct parse is usually
  // enough. As a last resort, keep only lines that look like records.
  var result = parseLineAnalysisFormat(response);
  if (result.questions.isNotEmpty ||
      result.answers.isNotEmpty ||
      result.notes.isNotEmpty) {
    return result;
  }

  final cleaned = response
      .replaceAll(RegExp(r'```[a-zA-Z]*'), '')
      .replaceAll('```', '')
      .split('\n')
      .where((l) => l.trim().startsWith('TYPE='))
      .join('\n');

  return parseLineAnalysisFormat(cleaned);
}
