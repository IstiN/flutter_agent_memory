import 'package:flutter_agent_memory/src/models/memory_level.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryLevel', () {
    test('constants are ordered raw < consolidated < concept', () {
      expect(MemoryLevel.raw, 1);
      expect(MemoryLevel.consolidated, 2);
      expect(MemoryLevel.concept, 3);
      expect(MemoryLevel.raw < MemoryLevel.consolidated, isTrue);
      expect(MemoryLevel.consolidated < MemoryLevel.concept, isTrue);
    });

    test('nameOf returns correct labels', () {
      expect(MemoryLevel.nameOf(MemoryLevel.raw), 'raw');
      expect(MemoryLevel.nameOf(MemoryLevel.consolidated), 'consolidated');
      expect(MemoryLevel.nameOf(MemoryLevel.concept), 'concept');
      expect(MemoryLevel.nameOf(99), 'raw');
    });

    test('fromName resolves known names case-insensitively', () {
      expect(MemoryLevel.fromName('raw'), MemoryLevel.raw);
      expect(MemoryLevel.fromName('Consolidated'), MemoryLevel.consolidated);
      expect(MemoryLevel.fromName('CONCEPT'), MemoryLevel.concept);
      expect(MemoryLevel.fromName(null), isNull);
      expect(MemoryLevel.fromName(''), isNull);
      expect(MemoryLevel.fromName('unknown'), isNull);
    });

    test('normalize clamps values to valid levels', () {
      expect(MemoryLevel.normalize(null), MemoryLevel.raw);
      expect(MemoryLevel.normalize(0), MemoryLevel.raw);
      expect(MemoryLevel.normalize(1), MemoryLevel.raw);
      expect(MemoryLevel.normalize(2), MemoryLevel.consolidated);
      expect(MemoryLevel.normalize(3), MemoryLevel.concept);
      expect(MemoryLevel.normalize(99), MemoryLevel.concept);
    });
  });
}
