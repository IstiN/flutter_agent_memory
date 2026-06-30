import 'package:flutter_agent_memory/src/models/relation.dart';
import 'package:test/test.dart';

void main() {
  group('Relation', () {
    test('serializes relation without weight', () {
      const relation = Relation(
        source: 'n_0001',
        target: 'n_0002',
        type: RelationType.supports,
      );
      expect(relation.toFrontmatterString(), 'supports|n_0002');
    });

    test('serializes relation with non-default weight', () {
      const relation = Relation(
        source: 'n_0001',
        target: 'n_0002',
        type: RelationType.relatedTo,
        weight: 0.75,
      );
      expect(relation.toFrontmatterString(), 'related_to|n_0002|0.75');
    });

    test('parses compact frontmatter string', () {
      final relation = Relation.fromFrontmatterString(
        'n_0001',
        'contradicts|n_0003',
      );
      expect(relation.source, 'n_0001');
      expect(relation.target, 'n_0003');
      expect(relation.type, 'contradicts');
      expect(relation.weight, 1.0);
    });

    test('parses compact frontmatter string with weight', () {
      final relation = Relation.fromFrontmatterString(
        'n_0001',
        'supports|n_0002|1.50',
      );
      expect(relation.type, 'supports');
      expect(relation.target, 'n_0002');
      expect(relation.weight, 1.5);
    });

    test('falls back to related_to for empty type', () {
      final relation = Relation.fromFrontmatterString('n_0001', '|n_0002');
      expect(relation.type, RelationType.relatedTo);
    });

    test('toJson includes optional validity dates', () {
      const relation = Relation(
        source: 'n_0001',
        target: 'n_0002',
        type: RelationType.supports,
        validFrom: '2025-01-01T00:00:00Z',
        validUntil: '2025-12-31T23:59:59Z',
      );
      final json = relation.toJson();
      expect(json['source'], 'n_0001');
      expect(json['target'], 'n_0002');
      expect(json['type'], 'supports');
      expect(json['validFrom'], '2025-01-01T00:00:00Z');
      expect(json['validUntil'], '2025-12-31T23:59:59Z');
    });
  });

  group('RelationType', () {
    test('normalize returns known types', () {
      expect(RelationType.normalize('supports'), RelationType.supports);
      expect(RelationType.normalize('Authored By'), RelationType.authoredBy);
    });

    test('normalize falls back to related_to', () {
      expect(RelationType.normalize('unknown'), RelationType.relatedTo);
      expect(RelationType.normalize(null), RelationType.relatedTo);
    });
  });
}
