import 'dart:convert';

import 'package:args/args.dart';

import 'command_registry.dart';

/// Builds a structured skill/cheat-sheet for LLM agents.
///
/// The output explains what `agent_memory` does, how to configure providers,
/// and how to invoke each command. It is generated from the command registry,
/// so it stays in sync with the CLI.
String buildSkillHelp({String format = 'markdown'}) {
  final commands = agentMemoryCommands;
  final parser = buildRootParser();

  if (format.toLowerCase() == 'json') {
    return _buildJson(commands, parser);
  }

  return _buildMarkdown(commands, parser);
}

String _buildMarkdown(List<CliCommand> commands, ArgParser rootParser) {
  final buffer = StringBuffer();

  buffer.writeln('# agent_memory skill');
  buffer.writeln();
  buffer.writeln('`agent_memory` is a Dart memory / knowledge-base framework.');
  buffer.writeln('It turns unstructured text, images, or directories into a structured,');
  buffer.writeln('Obsidian-compatible Markdown knowledge base of questions, answers,');
  buffer.writeln('notes, and people, powered by any OpenAI-compatible LLM.');
  buffer.writeln();
  buffer.writeln('## What the framework does');
  buffer.writeln();
  buffer.writeln('1. **Ingest** raw text, images, or whole directories via `process`.');
  buffer.writeln('2. **Extract** questions, answers, and notes with an LLM.');
  buffer.writeln('3. **Link** answers to questions and notes to topics, areas, and people.');
  buffer.writeln('4. **Build** a Markdown knowledge base:');
  buffer.writeln('   `questions/`, `answers/`, `notes/`, `topics/`, `areas/`, `people/`, `stats/`, `INDEX.md`.');
  buffer.writeln('5. **Search** by explicit tags or by natural language (AI generates tags).');
  buffer.writeln('6. **Remember** agent facts via `memory add`, query them via `memory ask`, and manage them via `memory list/update/delete/rank`.');
  buffer.writeln();
  buffer.writeln('## Provider configuration');
  buffer.writeln();
  buffer.writeln('Place a `.env` file in the working directory, or set environment variables:');
  buffer.writeln();
  buffer.writeln('```bash');
  buffer.writeln('# OpenAI');
  buffer.writeln('OPENAI_API_KEY=sk-...');
  buffer.writeln('OPENAI_MODEL=gpt-4o');
  buffer.writeln();
  buffer.writeln('# OpenRouter');
  buffer.writeln('OPENROUTER_API_KEY=sk-or-...');
  buffer.writeln('OPENROUTER_MODEL=openai/gpt-4o');
  buffer.writeln();
  buffer.writeln('# Ollama (OpenAI-compatible endpoint)');
  buffer.writeln('OLLAMA_BASE_URL=https://ollama.com');
  buffer.writeln('OLLAMA_API_KEY=your_key_here');
  buffer.writeln('OLLAMA_MODEL=ministral-3:14b');
  buffer.writeln('```');
  buffer.writeln();
  buffer.writeln('## Commands');
  buffer.writeln();
  buffer.writeln('| Command | Description |');
  buffer.writeln('|--------|-------------|');
  for (final command in commands) {
    buffer.writeln('| `${command.name}` | ${command.description} |');
  }
  buffer.writeln();
  buffer.writeln('## Command details');
  buffer.writeln();

  for (final command in commands) {
    buffer.writeln('### `${command.name}`');
    buffer.writeln();
    buffer.writeln(command.description);
    buffer.writeln();

    final subparser = rootParser.commands[command.name]!;
    final options = subparser.options.values;

    if (options.isNotEmpty) {
      buffer.writeln('**Parameters:**');
      buffer.writeln();
      for (final option in options) {
        final abbr = option.abbr != null ? '-${option.abbr}, ' : '';
        final name = '--${option.name}';
        final defaults = option.defaultsTo != null ? ' (defaults to `${option.defaultsTo}`)' : '';
        final mandatory = option.mandatory ? ' **(mandatory)**' : '';
        buffer.writeln('- `$abbr$name`$mandatory$defaults: ${option.help ?? ''}');
      }
      buffer.writeln();
    }

    if (command.subcommands.isNotEmpty) {
      buffer.writeln('**Subcommands:**');
      buffer.writeln();
      for (final sub in command.subcommands) {
        buffer.writeln('- `${sub.name}` — ${sub.description}');
        final subSubparser = subparser.commands[sub.name];
        if (subSubparser != null && subSubparser.options.isNotEmpty) {
          for (final option in subSubparser.options.values) {
            final abbr = option.abbr != null ? '-${option.abbr}, ' : '';
            final name = '--${option.name}';
            final defaults = option.defaultsTo != null ? ' (defaults to `${option.defaultsTo}`)' : '';
            final mandatory = option.mandatory ? ' **(mandatory)**' : '';
            buffer.writeln('  - `$abbr$name`$mandatory$defaults: ${option.help ?? ''}');
          }
        }
      }
      buffer.writeln();
    }
  }

  buffer.writeln('## Examples');
  buffer.writeln();
  buffer.writeln('```bash');
  buffer.writeln('# Process a file');
  buffer.writeln('agent_memory process -i meeting_notes.txt -o kb -s meetings --verbose');
  buffer.writeln();
  buffer.writeln('# Search with natural language');
  buffer.writeln('agent_memory search -o kb -q "How do we handle errors in Dart?" --show-tags');
  buffer.writeln();
  buffer.writeln('# Add agent memory and ask it back');
  buffer.writeln('agent_memory memory add -t note -x "Use Result type for error handling"');
  buffer.writeln('agent_memory memory ask -q "How do we handle errors?"');
  buffer.writeln('```');

  return buffer.toString();
}

String _buildJson(List<CliCommand> commands, ArgParser rootParser) {
  final json = <String, dynamic>{
    'tool': 'agent_memory',
    'description':
        'A Dart memory/knowledge-base framework that turns unstructured text, images, or directories into a structured Markdown KB and provides agent memory CRUD.',
    'configuration': {
      'env_file': '.env',
      'providers': ['openai', 'openrouter', 'ollama'],
    },
    'commands': commands.map((command) {
      final subparser = rootParser.commands[command.name]!;
      return {
        'name': command.name,
        'description': command.description,
        'options': _optionsToJson(subparser),
        'subcommands': command.subcommands.map((sub) {
          final subSubparser = subparser.commands[sub.name];
          return {
            'name': sub.name,
            'description': sub.description,
            'options': subSubparser != null ? _optionsToJson(subSubparser) : <Map<String, dynamic>>[],
          };
        }).toList(),
      };
    }).toList(),
  };

  return const JsonEncoder.withIndent('  ').convert(json);
}

List<Map<String, dynamic>> _optionsToJson(ArgParser parser) {
  return parser.options.values.map((option) {
    return <String, dynamic>{
      'name': option.name,
      'abbr': option.abbr,
      'help': option.help,
      'mandatory': option.mandatory,
      'defaultsTo': option.defaultsTo,
    };
  }).toList();
}
