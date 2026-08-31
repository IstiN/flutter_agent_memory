import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryIdScheme', () {
    test('allocate produces <prefix>_<index>_<hash> format', () {
      final id = MemoryIdScheme.allocate('n', 123, 'Some durable fact.');
      expect(id, matches(r'^n_0123_[0-9a-f]{4}$'));
    });

    test('hash suffix is deterministic and content-based', () {
      final a = MemoryIdScheme.hashSuffix('Release is frozen on Friday.');
      final b = MemoryIdScheme.hashSuffix('Release is frozen on Friday.');
      expect(a, b);
      expect(a, hasLength(MemoryIdScheme.idHashLength));
    });

    test('hash suffix normalizes casing and whitespace', () {
      final a = MemoryIdScheme.hashSuffix('  Hello   World ');
      final b = MemoryIdScheme.hashSuffix('hello world');
      expect(a, b);
    });

    test('different texts produce different suffixes', () {
      expect(
        MemoryIdScheme.hashSuffix('fact one'),
        isNot(MemoryIdScheme.hashSuffix('fact two')),
      );
    });

    test('answersQuestion discriminator changes the suffix', () {
      final plain = MemoryIdScheme.hashSuffix('yes');
      final forQ1 = MemoryIdScheme.hashSuffix(
        'yes',
        answersQuestion: 'q_0001_ab12',
      );
      final forQ2 = MemoryIdScheme.hashSuffix(
        'yes',
        answersQuestion: 'q_0002_cd34',
      );
      expect(forQ1, isNot(plain));
      expect(forQ1, isNot(forQ2));
    });

    test('empty answersQuestion is not a discriminator', () {
      expect(
        MemoryIdScheme.hashSuffix('yes', answersQuestion: ''),
        MemoryIdScheme.hashSuffix('yes'),
      );
    });

    test('parseIndex handles legacy and suffixed ids', () {
      expect(MemoryIdScheme.parseIndex('n_0001'), 1);
      expect(MemoryIdScheme.parseIndex('n_0447_a1b2'), 447);
      expect(MemoryIdScheme.parseIndex('q_10000'), 10000);
      expect(MemoryIdScheme.parseIndex('q_10000_f0f0'), 10000);
      expect(MemoryIdScheme.parseIndex('garbage'), isNull);
      expect(MemoryIdScheme.parseIndex('x_0001'), isNull);
    });

    test('isLegacy distinguishes the two formats', () {
      expect(MemoryIdScheme.isLegacy('n_0001'), isTrue);
      expect(MemoryIdScheme.isLegacy('n_0001_a1b2'), isFalse);
      expect(MemoryIdScheme.isLegacy('nope'), isFalse);
    });

    test('isValid accepts both formats and rejects noise', () {
      expect(MemoryIdScheme.isValid('a_0007'), isTrue);
      expect(MemoryIdScheme.isValid('a_0007_dead'), isTrue);
      expect(MemoryIdScheme.isValid('a_0007_nothex!'), isFalse);
      expect(MemoryIdScheme.isValid('p_0001'), isFalse);
    });

    test('index pads to four digits but allows more', () {
      expect(MemoryIdScheme.allocate('q', 7, 't'), startsWith('q_0007_'));
      expect(MemoryIdScheme.allocate('q', 12345, 't'), startsWith('q_12345_'));
    });
  });
}
