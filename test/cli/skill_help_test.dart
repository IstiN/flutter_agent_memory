import 'dart:convert';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:test/test.dart';

void main() {
  group('skill help', () {
    test('markdown skill help mentions every command', () {
      final markdown = buildSkillHelp(format: 'markdown');

      for (final command in agentMemoryCommands) {
        expect(markdown, contains('`${command.name}`'),
            reason: 'Skill help should reference command "${command.name}"');
        expect(markdown, contains(command.description),
            reason: 'Skill help should describe command "${command.name}"');
      }

      expect(markdown, contains('What the framework does'));
      expect(markdown, contains('Provider configuration'));
      expect(markdown, contains('Command details'));
      expect(markdown, contains('Examples'));
    });

    test('json skill help is valid and contains every command', () {
      final jsonText = buildSkillHelp(format: 'json');
      final json = jsonDecode(jsonText) as Map<String, dynamic>;

      expect(json['tool'], 'agent_memory');
      expect(json['description'], isNotEmpty);
      expect(json['commands'], isA<List>());

      final commandNames = (json['commands'] as List)
          .cast<Map<String, dynamic>>()
          .map((c) => c['name'] as String)
          .toSet();

      for (final command in agentMemoryCommands) {
        expect(commandNames, contains(command.name),
            reason: 'JSON skill help should contain command "${command.name}"');
      }
    });
  });
}
