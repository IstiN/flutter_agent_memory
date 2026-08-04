import 'package:flutter_agent_memory/src/models/note.dart';
import 'package:flutter_agent_memory/src/models/relation.dart';
import 'package:test/test.dart';

void main() {
  group('Note.toJson', () {
    const base = Note(
      id: 'n_1',
      text: 'text',
      area: 'dev',
      topics: [],
      tags: [],
      author: 'A',
      date: '2024-01-01',
      answersQuestions: [],
      links: [],
    );

    test('includes base fields', () {
      final json = base.toJson();
      expect(json['id'], 'n_1');
      expect(json['text'], 'text');
      expect(json['area'], 'dev');
    });

    test('omits empty optional fields', () {
      final json = base.toJson();
      expect(json.containsKey('answersQuestions'), isFalse);
      expect(json.containsKey('memoryType'), isFalse);
      expect(json.containsKey('validFrom'), isFalse);
      expect(json.containsKey('validUntil'), isFalse);
      expect(json.containsKey('relations'), isFalse);
    });

    test('includes answersQuestions when non-empty', () {
      final json = base.copyWith(answersQuestions: const ['q_1']).toJson();
      expect(json['answersQuestions'], ['q_1']);
    });

    test('includes memoryType when non-empty', () {
      final json = base.copyWith(memoryType: 'fact').toJson();
      expect(json['memoryType'], 'fact');
    });

    test('includes validity dates when non-empty', () {
      final json = base.copyWith(
        validFrom: '2024-01-01',
        validUntil: '2024-12-31',
      ).toJson();
      expect(json['validFrom'], '2024-01-01');
      expect(json['validUntil'], '2024-12-31');
    });

    test('includes level only when not raw', () {
      final raw = base.toJson();
      expect(raw.containsKey('level'), isFalse);

      final concept = base.copyWith(level: 2).toJson();
      expect(concept['level'], 2);
    });

    test('includes relations when non-empty', () {
      final json = base.copyWith(
        relations: const [
          Relation(
            source: 'n_1',
            target: 'n_2',
            type: RelationType.supports,
          ),
        ],
      ).toJson();
      expect(json['relations'], ['supports|n_2']);
    });

    test('toString includes id, level, memoryType and author', () {
      final note = base.copyWith(
        memoryType: 'fact',
        level: 2,
      );
      expect(note.toString(), 'Note(n_1 L2 fact by A)');
    });
  });
}
