import 'package:flutter_agent_memory/src/utils/model_json_utils.dart';
import 'package:test/test.dart';

void main() {
  group('doubleFromJson', () {
    test('parses double', () {
      expect(doubleFromJson(3.14), 3.14);
    });

    test('parses int as double', () {
      expect(doubleFromJson(42), 42.0);
    });

    test('parses string double', () {
      expect(doubleFromJson('2.5'), 2.5);
    });

    test('returns default on null', () {
      expect(doubleFromJson(null), 0.0);
    });

    test('returns default on invalid string', () {
      expect(doubleFromJson('abc'), 0.0);
    });
  });

  group('intFromJson', () {
    test('parses int', () {
      expect(intFromJson(7), 7);
    });

    test('parses string int', () {
      expect(intFromJson('99'), 99);
    });

    test('returns default on null', () {
      expect(intFromJson(null), 0);
    });
  });

  group('stringListFromJson', () {
    test('parses list', () {
      expect(stringListFromJson(['a', 'b']), ['a', 'b']);
    });

    test('parses bracket string', () {
      expect(stringListFromJson("[a, b, c]"), ['a', 'b', 'c']);
    });

    test('parses quoted bracket string', () {
      expect(stringListFromJson("['a', \"b\"]"), ['a', 'b']);
    });

    test('returns single string as list', () {
      expect(stringListFromJson('hello'), ['hello']);
    });

    test('returns empty for null', () {
      expect(stringListFromJson(null), isEmpty);
    });

    test('returns empty for empty string', () {
      expect(stringListFromJson(''), isEmpty);
    });

    test('returns empty for empty brackets', () {
      expect(stringListFromJson('[]'), isEmpty);
    });
  });

  group('linkListFromJson', () {
    test('parses link objects', () {
      final links = linkListFromJson([
        {'url': 'https://example.com', 'title': 'Example'},
      ]);
      expect(links.length, 1);
      expect(links.first.url, 'https://example.com');
    });

    test('parses plain strings', () {
      final links = linkListFromJson(['https://example.com']);
      expect(links.first.url, 'https://example.com');
    });

    test('returns empty for null', () {
      expect(linkListFromJson(null), isEmpty);
    });
  });
}
