import 'package:args/args.dart';
import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:test/test.dart';

void main() {
  group('CLI command registry', () {
    test('every top-level command has a non-empty description', () {
      for (final command in agentMemoryCommands) {
        expect(command.name, isNotEmpty, reason: 'Command name must not be empty');
        expect(command.hasDescription, isTrue,
            reason: 'Command "${command.name}" is missing a description. '
                'Add it to agentMemoryCommands so that --help stays consistent.');
      }
    });

    test('every memory subcommand has a non-empty description', () {
      final memory = agentMemoryCommands.firstWhere((c) => c.name == 'memory');
      for (final sub in memory.subcommands) {
        expect(sub.name, isNotEmpty, reason: 'Subcommand name must not be empty');
        expect(sub.hasDescription, isTrue,
            reason: 'Memory subcommand "${sub.name}" is missing a description. '
                'Add it to the memory command subcommands.');
      }
    });

    test('every option has a non-empty help text', () {
      final parser = buildRootParser();
      final parsers = <ArgParser>[parser, ...parser.commands.values];
      for (final sub in parser.commands.values) {
        parsers.addAll(sub.commands.values);
      }

      for (final p in parsers) {
        for (final option in p.options.values) {
          expect(option.help, isNotNull,
              reason: 'Option "${option.name}" is missing a help text.');
          expect(option.help!.trim(), isNotEmpty,
              reason: 'Option "${option.name}" has an empty help text.');
        }
      }
    });

    test('--help output contains every top-level command and its description', () {
      final parser = buildRootParser();
      final buffer = StringBuffer();
      printAgentMemoryUsage(parser: parser, sink: buffer);
      final output = buffer.toString();

      for (final command in agentMemoryCommands) {
        expect(output, contains(command.name),
            reason: 'Help output should mention command "${command.name}"');
        expect(output, contains(command.description),
            reason: 'Help output should describe command "${command.name}"');
      }
    });

    test('--help output contains every memory subcommand and its description', () {
      final parser = buildRootParser();
      final buffer = StringBuffer();
      printAgentMemoryUsage(parser: parser, sink: buffer);
      final output = buffer.toString();

      final memory = agentMemoryCommands.firstWhere((c) => c.name == 'memory');
      for (final sub in memory.subcommands) {
        expect(output, contains(sub.name),
            reason: 'Help output should mention memory subcommand "${sub.name}"');
        expect(output, contains(sub.description),
            reason: 'Help output should describe memory subcommand "${sub.name}"');
      }
    });
  });
}
