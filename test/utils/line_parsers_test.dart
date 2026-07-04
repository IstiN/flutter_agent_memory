import 'package:flutter_agent_memory/src/utils/line_parsers.dart';
import 'package:test/test.dart';

void main() {
  group('parseTagGeneratorLines', () {
    test('parses TAG= lines', () {
      expect(
        parseTagGeneratorLines('TAG=dart\nTAG=flutter'),
        ['dart', 'flutter'],
      );
    });

    test('ignores surrounding whitespace and empty lines', () {
      expect(
        parseTagGeneratorLines('\n  TAG=dart  \n\nTAG=flutter\n'),
        ['dart', 'flutter'],
      );
    });

    test('falls back to JSON tags field', () {
      expect(
        parseTagGeneratorLines('{"tags": ["riverpod", "state"]}'),
        ['riverpod', 'state'],
      );
    });

    test('returns empty list when nothing matches', () {
      expect(parseTagGeneratorLines('just some text'), isEmpty);
    });
  });

  group('parseRerankerLines', () {
    test('parses RANKED_ID= lines', () {
      expect(
        parseRerankerLines('RANKED_ID=n_0002\nRANKED_ID=n_0001'),
        ['n_0002', 'n_0001'],
      );
    });

    test('falls back to JSON rankedIds field', () {
      expect(
        parseRerankerLines('{"rankedIds": ["n_0002", "n_0001"]}'),
        ['n_0002', 'n_0001'],
      );
    });
  });

  group('parseQaMappingLines', () {
    test('parses MAPPING lines', () {
      final result = parseQaMappingLines(
        'MAPPING | answerId=a_1 | questionId=q_1 | confidence=0.9',
      );
      expect(result.mappings, hasLength(1));
      expect(result.mappings.first.answerId, 'a_1');
      expect(result.mappings.first.questionId, 'q_1');
      expect(result.mappings.first.confidence, 0.9);
    });

    test('falls back to JSON mappings field', () {
      final result = parseQaMappingLines(
        '{"mappings": [{"answerId": "a_1", "questionId": "q_1", "confidence": 0.8}]}',
      );
      expect(result.mappings, hasLength(1));
      expect(result.mappings.first.confidence, 0.8);
    });
  });

  group('parseConsolidationLines', () {
    test('parses SUMMARY and SKILL lines', () {
      final response = '''
SUMMARY=First paragraph.
SUMMARY=Second paragraph.
SKILL | ID=sk_1 | TITLE=Handle errors | INSTRUCTION=Use try/catch. | TAGS=dart;errors
''';
      final result = parseConsolidationLines(response);
      expect(result.summary, 'First paragraph.\n\nSecond paragraph.');
      expect(result.skills, hasLength(1));
      expect(result.skills.first.id, 'sk_1');
      expect(result.skills.first.title, 'Handle errors');
      expect(result.skills.first.instruction, 'Use try/catch.');
      expect(result.skills.first.tags, ['dart', 'errors']);
    });

    test('falls back to JSON', () {
      final result = parseConsolidationLines(
        '{"summary": "S", "skills": [{"id": "sk_1", "title": "T", "instruction": "I", "tags": ["x"]}]}',
      );
      expect(result.summary, 'S');
      expect(result.skills.first.title, 'T');
    });
  });
}
