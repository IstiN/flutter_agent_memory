import 'dart:io';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:test/test.dart';

/// The Dart policy constants must mirror the canonical markdown documents
/// in docs/memory/ — agents read one or the other, so they may never drift.
void main() {
  String doc(String name) =>
      File('docs/memory/$name').readAsStringSync().trim();

  group('MemoryPolicy', () {
    test('memoryAddPolicy matches docs/memory/memory_add_policy.md', () {
      expect(MemoryPolicy.memoryAddPolicy.trim(), doc('memory_add_policy.md'));
    });

    test('tagTaxonomy matches docs/memory/tag_taxonomy.md', () {
      expect(MemoryPolicy.tagTaxonomy.trim(), doc('tag_taxonomy.md'));
    });

    test('consolidationRules matches docs/memory/consolidation_rules.md', () {
      expect(
        MemoryPolicy.consolidationRules.trim(),
        doc('consolidation_rules.md'),
      );
    });

    test('policies are non-trivial and mention key rules', () {
      expect(MemoryPolicy.memoryAddPolicy.length, greaterThan(500));
      expect(MemoryPolicy.memoryAddPolicy, contains('supersede'));
      expect(MemoryPolicy.tagTaxonomy, contains('#source_'));
      expect(
        MemoryPolicy.consolidationRules,
        contains('ConcurrentRevisionException'),
      );
    });
  });
}
