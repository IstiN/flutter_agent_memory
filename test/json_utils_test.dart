import 'dart:convert';

import 'package:flutter_agent_memory/src/utils/json_utils.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeJson', () {
    test('strips think blocks and markdown fences', () {
      const response = '''<think>some reasoning</think>
```json
{"tags": ["flutter", "dart"],}
```''';
      final result = sanitizeJson(response);
      expect(jsonDecode(result), {
        'tags': ['flutter', 'dart'],
      });
    });

    test('repairs unquoted object values containing commas', () {
      const broken = '''
{
  "id": "n_3",
  "text": Docker image for Dart backend: Use a multi-stage Dockerfile starting from dart:stable, build AOT snapshot, then copy to runtime image.,
  "area": "Docker"
}
''';
      final result = sanitizeJson(broken);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['id'], 'n_3');
      expect(
        decoded['text'],
        'Docker image for Dart backend: Use a multi-stage Dockerfile starting from dart:stable, build AOT snapshot, then copy to runtime image.',
      );
      expect(decoded['area'], 'Docker');
    });

    test('repairs unquoted array items', () {
      const broken = '{"tags": [Flutter, Dart, CI/CD]}';
      final result = sanitizeJson(broken);
      expect(jsonDecode(result), {
        'tags': ['Flutter', 'Dart', 'CI/CD'],
      });
    });

    test('does not quote true, false, null or numbers', () {
      const broken = '{"a": true, "b": false, "c": null, "d": 0.9, "e": -1}';
      final result = sanitizeJson(broken);
      expect(jsonDecode(result), {
        'a': true,
        'b': false,
        'c': null,
        'd': 0.9,
        'e': -1,
      });
    });

    test('repairs trailing commas in arrays and objects', () {
      const broken = '{"tags": ["a", "b",], "value": 1,}';
      final result = sanitizeJson(broken);
      expect(jsonDecode(result), {
        'tags': ['a', 'b'],
        'value': 1,
      });
    });

    test('repairs unterminated string values with embedded newlines', () {
      const broken = '''{
  "answeredBy": "Uladzimir Klyshevich
}''';
      final result = sanitizeJson(broken);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['answeredBy'], 'Uladzimir Klyshevich');
    });

    test('repairs missing colons after quoted keys', () {
      const broken = '''{
  "author "Uladzimir Klyshevich",
  "text "I don't need IDE."
}''';
      final result = sanitizeJson(broken);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['author'], 'Uladzimir Klyshevich');
      expect(decoded['text'], "I don't need IDE.");
    });

    test('repairs corrupted keys like per into text', () {
      const broken = '''{
  "author": "Uladzimir Klyshevich",
  "per": "I don't like superset because it's slow."
}''';
      final result = sanitizeJson(broken);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['text'], "I don't like superset because it's slow.");
    });

    test('repairs malformed Gemma dates', () {
      const broken = '{"d1": "202310-27T0500Z", "d2": "202310-7T00Z", "d3": "202310-7000"}';
      final result = sanitizeJson(broken);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['d1'], '2023-10-27T05:00:00Z');
      expect(decoded['d2'], '2023-10-07T00:00:00Z');
      expect(decoded['d3'], isNotEmpty);
    });

    test('repairs unquoted object keys', () {
      const broken = '{id: "n_1", text: "hello world", area: "gen"}';
      final result = sanitizeJson(broken);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['id'], 'n_1');
      expect(decoded['text'], 'hello world');
      expect(decoded['area'], 'gen');
    });

    test('repairs broken array objects', () {
      const broken = '{"answers": [{"id": "a_1", "text": "first"\n{"id": "a_2", "text": "second"}]}';
      final result = sanitizeJson(broken);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      final answers = decoded['answers'] as List<dynamic>;
      expect(answers.length, 2);
      expect(answers[1]['id'], 'a_2');
    });

    test('extracts json from plain markdown fence', () {
      const response = '''```
{"ok": true}
```''';
      expect(sanitizeAndDecodeJson(response), {'ok': true});
    });

    test('strips control characters', () {
      const broken = '{"text": "hello\x00world"}';
      final result = sanitizeJson(broken);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['text'], 'helloworld');
    });
  });

  group('recoverPartialAnalysisJson', () {
    test('recovers complete objects before token soup', () {
      const broken = '''
{
  "questions": [
    {"id": "q_1", "author": "A", "text": "x", "date": "2024-05-20T00:26:01Z", "area": "a", "topics": [], "tags": []},
    {"id": "q_2", "author": "B", "text": "y", "date": "2024-05-20T00:26:06Z", "area": "a", "topics": [], "tags": []}
  ],
  "answers": [
    {"id": "a_1", "author": "A", "text": "x", "date": "2024-05-20T00:26:01Z", "area": "a", "topics": [], "tags": [], "quality": 1.0}
  ],
  "notes": []
}
0000000000 garbage here
''';
      final result = recoverPartialAnalysisJson(broken);
      expect(result['questions'], hasLength(2));
      expect(result['answers'], hasLength(1));
      expect(result['notes'], hasLength(0));
    });

    test('recovers objects from a truncated Gemma response', () {
      const broken = r'''
{
  "questions": [
    {"id": "q_1", "author": "Ira", "text": "And not good.", "date": "2024-05-20T00:26:01Z", "area": "general", "topics": [], "tags": []},
    {"id": "q_2", "author": "Alex", "text": "Video.", "date": "2024-05-20T00:26:06Z", "area": "general", "topics": [], "tags": []}
  ],
  "answers": [
    {"id": "a_1", "author": "Ira", "text": "And not good.", "date": "2024-05-20T00:26:01Z", "area": "general", "topics": [], "tags": [], "quality": 0.8}
  ],
  "notes": [nonsense
''';
      final result = recoverPartialAnalysisJson(broken);
      expect(result['questions'], hasLength(2));
      expect(result['answers'], hasLength(1));
      expect(result['notes'], hasLength(0));
    });
  });
}
