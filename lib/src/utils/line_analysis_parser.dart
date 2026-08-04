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
  final cleanedResponse = _cleanResponse(response);
  final starts = _recordBoundaries(cleanedResponse);
  final questions = <Question>[];
  final answers = <Answer>[];
  final notes = <Note>[];

  for (var i = 0; i < starts.length; i++) {
    final start = starts[i];
    final end = i + 1 < starts.length ? starts[i + 1] : cleanedResponse.length;
    final record = cleanedResponse.substring(start, end).trim();
    final entity = _parseRecord(record);
    switch (entity) {
      case final Question q:
        questions.add(q);
      case final Answer a:
        answers.add(a);
      case final Note n:
        notes.add(n);
      case null:
        break;
    }
  }

  return AnalysisResult(
    questions: questions,
    answers: answers,
    notes: notes,
  );
}

String _cleanResponse(String response) =>
    response
        .replaceAll('</raw_input>', '')
        .replaceAll(RegExp(r'</output\b[^>]*>'), '')
        .replaceAll('</output_format>', '')
        .replaceAll('</format>', '')
        .replaceAll('<output>', '')
        .replaceAll('</prompt>', '')
        .replaceAll(RegExp(r'</(?:answer|question|note)\b[^>]*>'), '')
        .replaceAll(RegExp(r'<(?:output|answer|question|note)>'), '');

List<int> _recordBoundaries(String response) {
  final typeMatches = RegExp(r'TYPE=[A-Za-z]\b').allMatches(response);
  final starts = <int>[];
  for (final m in typeMatches) {
    if (m.start == 0) {
      starts.add(0);
    } else {
      final before = response[m.start - 1];
      if (before == '|' || before.trim().isEmpty) {
        starts.add(m.start);
      }
    }
  }
  return starts;
}

Object? _parseRecord(String record) {
  if (record.isEmpty) return null;
  if (!record.startsWith(RegExp(r'TYPE=[QAN]\b'))) return null;

  final fields = parseLabeledFields(record);
  final type = fields['TYPE'] ?? '';
  final id = fields['ID'] ?? '';
  if (id.isEmpty) return null;

  final base = _RecordBase.from(fields);

  return switch (type) {
    'Q' => _buildQuestion(id, fields, base),
    'A' => _buildAnswer(id, fields, base),
    'N' => _buildNote(id, fields, base),
    _ => null,
  };
}

Question _buildQuestion(
  String id,
  Map<String, String?> fields,
  _RecordBase b,
) =>
    Question(
      id: id,
      author: b.author,
      text: '',
      startTextRef: b.startRef,
      endTextRef: b.endRef,
      date: b.date,
      area: b.area,
      topics: b.topics,
      tags: b.tags,
      answeredBy: _normalizeEmpty(fields['ANSWERED_BY']),
      links: b.links,
    );

Answer _buildAnswer(
  String id,
  Map<String, String?> fields,
  _RecordBase b,
) =>
    Answer(
      id: id,
      author: b.author,
      text: '',
      startTextRef: b.startRef,
      endTextRef: b.endRef,
      date: b.date,
      area: b.area,
      topics: b.topics,
      tags: b.tags,
      answersQuestion: _normalizeEmpty(fields['ANSWERS_QUESTION']),
      quality: _parseDouble(fields['QUALITY']),
      links: b.links,
    );

Note _buildNote(
  String id,
  Map<String, String?> fields,
  _RecordBase b,
) =>
    Note(
      id: id,
      text: '',
      startTextRef: b.startRef,
      endTextRef: b.endRef,
      area: b.area,
      topics: b.topics,
      tags: b.tags,
      author: b.author,
      date: b.date,
      answersQuestions: const [],
      links: b.links,
      memoryType: fields['MEMORY_TYPE'],
    );

class _RecordBase {
  final String author;
  final String date;
  final String area;
  final List<String> topics;
  final List<String> tags;
  final List<Link> links;
  final String? startRef;
  final String? endRef;

  _RecordBase({
    required this.author,
    required this.date,
    required this.area,
    required this.topics,
    required this.tags,
    required this.links,
    required this.startRef,
    required this.endRef,
  });

  factory _RecordBase.from(Map<String, String?> fields) => _RecordBase(
        author: fields['AUTHOR'] ?? '',
        date: fields['DATE'] ?? '',
        area: fields['AREA'] ?? 'general',
        topics: semicolonList(fields['TOPICS']),
        tags: semicolonList(fields['TAGS']),
        links: _parseLinks(fields['LINKS']),
        startRef: fields['START'],
        endRef: fields['END'],
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

const _emptySentinels = {'(empty)', 'empty', 'none', 'n/a', 'null'};

String? _normalizeEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (_emptySentinels.contains(trimmed.toLowerCase())) return null;
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
