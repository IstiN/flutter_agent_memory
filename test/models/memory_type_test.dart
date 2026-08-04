import 'package:flutter_agent_memory/src/models/memory_type.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryType.normalize', () {
    test('returns null for null or empty input', () {
      expect(MemoryType.normalize(null), isNull);
      expect(MemoryType.normalize(''), isNull);
      expect(MemoryType.normalize('  '), 'generic');
    });

    test('normalizes known types to lowercase', () {
      expect(MemoryType.normalize('Fact'), 'fact');
      expect(MemoryType.normalize('EVENT'), 'event');
      expect(MemoryType.normalize('  Observation  '), 'observation');
    });

    test('falls back to generic for unknown values', () {
      expect(MemoryType.normalize('custom'), 'generic');
      expect(MemoryType.normalize('123'), 'generic');
    });
  });
}
