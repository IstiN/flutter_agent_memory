import '../models/consolidation_result.dart';
import '../models/qa_mapping_result.dart';
import '../utils/json_utils.dart';
import 'line_parser_utils.dart';

/// Collection of lightweight line-oriented parsers for the new prompt formats.

/// Parses tag-generator output into a list of tags.
///
/// Expected lines: `TAG=dart`, `TAG=flutter-state-management`
List<String> parseTagGeneratorLines(String response) {
  final cleaned = _stripCodeBlocks(response);
  final tags = cleaned
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.startsWith('TAG='))
      .map((l) => l.substring(4).trim())
      .where((t) => t.isNotEmpty)
      .toList();
  if (tags.isNotEmpty) return tags;
  // Fallback for models that still return JSON.
  if (cleaned.trim().startsWith('{')) {
    try {
      final json = sanitizeAndDecodeJson(cleaned) as Map<String, dynamic>;
      return (json['tags'] as List? ?? [])
          .map((e) => e.toString())
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (_) {}
  }
  return tags;
}

/// Parses reranker output into an ordered list of record IDs.
///
/// Expected lines: `RANKED_ID=n_0002`
List<String> parseRerankerLines(String response) {
  final cleaned = _stripCodeBlocks(response);
  final ranked = cleaned
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.startsWith('RANKED_ID='))
      .map((l) => l.substring(10).trim())
      .where((id) => id.isNotEmpty)
      .toList();
  if (ranked.isNotEmpty) return ranked;
  if (cleaned.trim().startsWith('{')) {
    try {
      final json = sanitizeAndDecodeJson(cleaned) as Map<String, dynamic>;
      return (json['rankedIds'] as List? ?? [])
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {}
  }
  return ranked;
}

/// Parses QA-mapping output into a list of mappings.
///
/// Expected lines:
/// `MAPPING | answerId=a_1 | questionId=q_1 | confidence=0.9`
QAMappingResult parseQaMappingLines(String response) {
  final cleaned = _stripCodeBlocks(response);
  final mappings = _parseMappingLines(cleaned);
  if (mappings.isNotEmpty) return QAMappingResult(mappings: mappings);
  return _parseQaJsonFallback(cleaned);
}

List<Mapping> _parseMappingLines(String cleaned) {
  final mappings = <Mapping>[];
  for (final line in cleaned.split('\n')) {
    final mapping = _parseMappingLine(line);
    if (mapping != null) mappings.add(mapping);
  }
  return mappings;
}

Mapping? _parseMappingLine(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('MAPPING')) return null;
  final fields = parsePipeFields(trimmed);
  final answerId = fields['ANSWERID'] ?? '';
  final questionId = fields['QUESTIONID'] ?? '';
  final confidence = double.tryParse(fields['CONFIDENCE'] ?? '') ?? 0.0;
  if (answerId.isEmpty || questionId.isEmpty) return null;
  return Mapping(
    answerId: answerId,
    questionId: questionId,
    confidence: confidence,
  );
}

QAMappingResult _parseQaJsonFallback(String cleaned) {
  if (cleaned.trim().startsWith('{')) {
    try {
      final json = sanitizeAndDecodeJson(cleaned) as Map<String, dynamic>;
      return QAMappingResult.fromJson(json);
    } catch (_) {}
  }
  return const QAMappingResult(mappings: []);
}

/// Parses consolidation output into a summary and skill cards.
///
/// Expected lines:
/// `SUMMARY=First paragraph.`
/// `SKILL | ID=sk_1 | TITLE=... | INSTRUCTION=... | TAGS=...`
ConsolidationResult parseConsolidationLines(String response) {
  final cleaned = _stripCodeBlocks(response);
  final summaries = <String>[];
  final skills = <SkillCard>[];
  for (final line in cleaned.split('\n')) {
    _parseConsolidationLine(line, summaries, skills);
  }
  if (summaries.isNotEmpty || skills.isNotEmpty) {
    return _buildConsolidationResult(summaries, skills);
  }
  return _tryJsonFallback(cleaned) ?? _buildConsolidationResult(summaries, skills);
}

void _parseConsolidationLine(
  String line,
  List<String> summaries,
  List<SkillCard> skills,
) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return;
  if (trimmed.startsWith('SUMMARY=')) {
    final text = trimmed.substring(8).trim();
    if (text.isNotEmpty) summaries.add(text);
    return;
  }
  if (trimmed.startsWith('SKILL')) {
    final skill = _parseSkillLine(trimmed);
    if (skill != null) skills.add(skill);
  }
}

SkillCard? _parseSkillLine(String line) {
  final fields = parsePipeFields(line);
  final id = fields['ID'] ?? '';
  final title = fields['TITLE'] ?? '';
  if (id.isEmpty || title.isEmpty) return null;
  return SkillCard(
    id: id,
    title: title,
    instruction: fields['INSTRUCTION'] ?? '',
    tags: semicolonList(fields['TAGS']),
  );
}

ConsolidationResult _buildConsolidationResult(
  List<String> summaries,
  List<SkillCard> skills,
) =>
    ConsolidationResult(
      summary: summaries.isEmpty ? '' : summaries.join('\n\n'),
      skills: skills,
    );

ConsolidationResult? _tryJsonFallback(String cleaned) {
  if (!cleaned.trim().startsWith('{')) return null;
  try {
    final json = sanitizeAndDecodeJson(cleaned) as Map<String, dynamic>;
    return ConsolidationResult.fromJson(json);
  } catch (_) {
    return null;
  }
}

/// Strips markdown code fences and common XML artifacts from model output.
String _stripCodeBlocks(String response) {
  return response
      .replaceAll(RegExp(r'```[a-zA-Z]*'), '')
      .replaceAll('```', '')
      .replaceAll('</output>', '')
      .replaceAll('</format>', '')
      .replaceAll('</prompt>', '')
      .trim();
}
