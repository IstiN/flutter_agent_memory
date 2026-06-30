import 'dart:io';

import 'package:args/args.dart';

/// Metadata for a CLI command or subcommand.
///
/// Using a registry guarantees that every command has a description and that
/// the help output stays consistent. When you add a new command, add it here;
/// the help-consistency test will fail if the description is missing.
class CliCommand {
  final String name;
  final String description;
  final ArgParser Function() buildParser;
  final List<CliCommand> subcommands;

  const CliCommand({
    required this.name,
    required this.description,
    required this.buildParser,
    this.subcommands = const [],
  });

  bool get hasDescription => description.trim().isNotEmpty;
}

/// Top-level commands exposed by the `agent_memory` CLI.
final List<CliCommand> agentMemoryCommands = [
  CliCommand(
    name: 'process',
    description: 'Analyze input text/images and build or update the knowledge base.',
    buildParser: _processCommandParser,
  ),
  CliCommand(
    name: 'regenerate',
    description: 'Regenerate structure files (topics, areas, people, stats) from existing Q/A/N records.',
    buildParser: _regenerateCommandParser,
  ),
  CliCommand(
    name: 'stats',
    description: 'Regenerate statistics, indexes, and the knowledge-base INDEX.md.',
    buildParser: _statsCommandParser,
  ),
  CliCommand(
    name: 'search-tags',
    description: 'Search knowledge-base records by explicit tags.',
    buildParser: _searchTagsCommandParser,
  ),
  CliCommand(
    name: 'search',
    description: 'Search the knowledge base using natural language (AI generates tags from the query).',
    buildParser: _searchCommandParser,
  ),
  CliCommand(
    name: 'skill',
    description: 'Show a structured skill/cheat-sheet for LLM agents (what the framework does and how to call it).',
    buildParser: _skillCommandParser,
  ),
  CliCommand(
    name: 'memory',
    description: 'Agent memory CRUD: add, ask, list, delete, rank, and update records.',
    buildParser: _memoryCommandParser,
    subcommands: [
      CliCommand(
        name: 'add',
        description: 'Add a new question, answer, or note to agent memory.',
        buildParser: _memoryAddCommandParser,
      ),
      CliCommand(
        name: 'ask',
        description: 'Ask a natural-language question against agent memory.',
        buildParser: _memoryAskCommandParser,
      ),
      CliCommand(
        name: 'list',
        description: 'List memory records, optionally filtered by type or tags.',
        buildParser: _memoryListCommandParser,
      ),
      CliCommand(
        name: 'delete',
        description: 'Delete a memory record by its id.',
        buildParser: _memoryDeleteCommandParser,
      ),
      CliCommand(
        name: 'rank',
        description: 'Show top-ranked memory records by access count, importance, or recency.',
        buildParser: _memoryRankCommandParser,
      ),
      CliCommand(
        name: 'update',
        description: 'Update text, tags, or importance of an existing memory record.',
        buildParser: _memoryUpdateCommandParser,
      ),
      CliCommand(
        name: 'consolidate',
        description: 'Consolidate memory records into a high-level MEMORY.md summary and skill cards.',
        buildParser: _memoryConsolidateCommandParser,
      ),
      CliCommand(
        name: 'relate',
        description: 'Add a typed relation between two memory records.',
        buildParser: _memoryRelateCommandParser,
      ),
      CliCommand(
        name: 'promote',
        description: 'Promote a note to a higher memory level (1 raw → 2 consolidated → 3 concept).',
        buildParser: _memoryPromoteCommandParser,
      ),
      CliCommand(
        name: 'graph',
        description: 'Regenerate the Obsidian-compatible GRAPH.md from the knowledge base.',
        buildParser: _memoryGraphCommandParser,
      ),
    ],
  ),
];

/// Builds the root ArgParser from the command registry.
ArgParser buildRootParser() {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage information.');

  for (final command in agentMemoryCommands) {
    parser.addCommand(command.name, _buildParser(command));
  }

  return parser;
}

/// Prints unified help to the given sink.
void printAgentMemoryUsage({ArgParser? parser, List<CliCommand>? commands, StringSink? sink}) {
  final output = sink ?? stdout;
  final rootParser = parser ?? buildRootParser();
  final rootCommands = commands ?? agentMemoryCommands;

  output.writeln('Usage: agent_memory <command> [options]');
  output.writeln();
  output.writeln('Commands:');
  for (final command in rootCommands) {
    output.writeln('  ${command.name.padRight(12)} ${command.description}');
  }
  output.writeln();
  output.writeln('Global options:');
  output.writeln(rootParser.usage);

  for (final entry in rootParser.commands.entries) {
    final sub = entry.value;
    final meta = rootCommands.firstWhere((c) => c.name == entry.key);
    if (sub.options.isNotEmpty || sub.commands.isNotEmpty || meta.subcommands.isNotEmpty) {
      output.writeln();
      output.writeln('${entry.key} options:');
      output.writeln(sub.usage);
      if (meta.subcommands.isNotEmpty) {
        output.writeln();
        output.writeln('  Subcommands:');
        for (final subCmd in meta.subcommands) {
          output.writeln('    ${subCmd.name.padRight(10)} ${subCmd.description}');
        }
      }
    }
  }
}

ArgParser _buildParser(CliCommand command) {
  final parser = command.buildParser();
  for (final sub in command.subcommands) {
    parser.addCommand(sub.name, _buildParser(sub));
  }
  return parser;
}

ArgParser _processCommandParser() => ArgParser()
  ..addOption('input', abbr: 'i', help: 'Input file path (use - for stdin)', mandatory: true)
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Output directory')
  ..addOption('source', abbr: 's', help: 'Source name (defaults to input file name)')
  ..addOption('provider', defaultsTo: 'openai', help: 'LLM provider: openai, openrouter or ollama')
  ..addOption('api-key', help: 'API key (defaults to OPENAI_API_KEY / OPENROUTER_API_KEY env)')
  ..addOption('base-url', help: 'Base URL for the chat completions endpoint')
  ..addOption('model', help: 'Model name (defaults to OPENAI_MODEL / OPENROUTER_MODEL env)')
  ..addOption('max-tokens', help: 'Max output tokens')
  ..addOption('temperature', help: 'Sampling temperature')
  ..addOption('mode', defaultsTo: 'full', help: 'Processing mode: full, process-only, aggregate-only')
  ..addFlag('clean', help: 'Clean output directory before processing')
  ..addFlag('verbose', abbr: 'v', help: 'Verbose output')
  ..addOption('analysis-instructions', help: 'Extra instructions for the analysis agent')
  ..addOption('aggregation-instructions', help: 'Extra instructions for the aggregation agent')
  ..addOption('qa-mapping-instructions', help: 'Extra instructions for the Q&A mapping agent');

ArgParser _regenerateCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Output directory')
  ..addOption('source', abbr: 's', defaultsTo: 'default', help: 'Source name')
  ..addFlag('verbose', abbr: 'v', help: 'Verbose output');

ArgParser _statsCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Output directory')
  ..addFlag('verbose', abbr: 'v', help: 'Verbose output');

ArgParser _searchTagsCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('tags', abbr: 't', help: 'Comma-separated tags to search for', mandatory: true)
  ..addFlag('match-any', help: 'Match any tag instead of all tags')
  ..addOption('type', help: 'Comma-separated entity types: question,answer,note')
  ..addFlag('json', help: 'Output results as JSON');

ArgParser _searchCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('query', abbr: 'q', help: 'Natural-language search query', mandatory: true)
  ..addOption('provider', defaultsTo: 'openai', help: 'LLM provider: openai, openrouter or ollama')
  ..addOption('api-key', help: 'API key')
  ..addOption('base-url', help: 'Base URL for the chat completions endpoint')
  ..addOption('model', help: 'Model name')
  ..addOption('max-tokens', help: 'Max output tokens')
  ..addOption('temperature', help: 'Sampling temperature')
  ..addFlag('match-all', help: 'Require all generated tags to match')
  ..addOption('type', help: 'Comma-separated entity types: question,answer,note')
  ..addFlag('json', help: 'Output results as JSON')
  ..addFlag('show-tags', help: 'Print generated tags before results');

ArgParser _memoryCommandParser() => ArgParser();

ArgParser _memoryAskCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('query', abbr: 'q', help: 'Natural-language question', mandatory: true)
  ..addOption('as-of', help: 'Only records known at this ISO date/time (e.g., 2025-03-15)')
  ..addOption('provider', defaultsTo: 'openai', help: 'LLM provider: openai, openrouter or ollama')
  ..addOption('api-key', help: 'API key')
  ..addOption('base-url', help: 'Base URL')
  ..addOption('model', help: 'Model name')
  ..addFlag('json', help: 'Output as JSON');

ArgParser _memoryListCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('type', help: 'Filter by type: question, answer, note')
  ..addOption('tags', help: 'Comma-separated tags')
  ..addOption('sort', defaultsTo: 'lastAccessed', help: 'Sort by: lastAccessed, accessCount, importance')
  ..addOption('limit', help: 'Max records to show')
  ..addOption('as-of', help: 'Only records known at this ISO date/time (e.g., 2025-03-15)')
  ..addOption('memory-type', help: 'Filter notes by memory type')
  ..addFlag('json', help: 'Output as JSON');

ArgParser _memoryDeleteCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('id', abbr: 'i', help: 'Record id', mandatory: true);

ArgParser _memoryRankCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('limit', defaultsTo: '10', help: 'Number of top records')
  ..addOption('sort', defaultsTo: 'accessCount', help: 'Sort by: accessCount, importance, lastAccessed')
  ..addFlag('json', help: 'Output as JSON');

ArgParser _memoryUpdateCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('id', abbr: 'i', help: 'Record id', mandatory: true)
  ..addOption('text', abbr: 'x', help: 'New text/content')
  ..addOption('tags', help: 'Comma-separated tags')
  ..addOption('importance', help: 'New importance score 0.0-1.0')
  ..addOption('memory-type', help: 'For notes: fact, event, observation, belief, decision, rule, experience')
  ..addOption('valid-from', help: 'ISO date from which the note is valid')
  ..addOption('valid-until', help: 'ISO date until which the note is valid')
  ..addOption('level', help: 'Memory level: 1 raw, 2 consolidated, 3 concept')
  ..addOption('provider', defaultsTo: 'openai', help: 'LLM provider: openai, openrouter or ollama')
  ..addOption('api-key', help: 'API key')
  ..addOption('base-url', help: 'Base URL')
  ..addOption('model', help: 'Model name');

ArgParser _memoryAddCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('type', abbr: 't', help: 'Record type: question, answer, note', mandatory: true)
  ..addOption('text', abbr: 'x', help: 'Record text/content', mandatory: true)
  ..addOption('author', abbr: 'a', defaultsTo: 'agent', help: 'Author name')
  ..addOption('area', help: 'Knowledge area')
  ..addOption('topics', help: 'Comma-separated topics')
  ..addOption('tags', help: 'Comma-separated tags')
  ..addOption('answers-question', help: 'For answers: id of the question being answered')
  ..addOption('importance', defaultsTo: '0.5', help: 'Importance score 0.0-1.0')
  ..addOption('memory-type', help: 'For notes: fact, event, observation, belief, decision, rule, experience')
  ..addOption('valid-from', help: 'ISO date from which the note is valid')
  ..addOption('valid-until', help: 'ISO date until which the note is valid')
  ..addOption('level', help: 'Memory level: 1 raw, 2 consolidated, 3 concept')
  ..addOption('provider', defaultsTo: 'openai', help: 'LLM provider: openai, openrouter or ollama')
  ..addOption('api-key', help: 'API key')
  ..addOption('base-url', help: 'Base URL')
  ..addOption('model', help: 'Model name');

ArgParser _memoryRelateCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('from', abbr: 'f', help: 'Source record id', mandatory: true)
  ..addOption('to', abbr: 't', help: 'Target record id', mandatory: true)
  ..addOption('type', abbr: 'y', help: 'Relation type', mandatory: true)
  ..addOption('weight', defaultsTo: '1.0', help: 'Edge weight 0.0-1.0');

ArgParser _memoryPromoteCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('id', abbr: 'i', help: 'Record id', mandatory: true)
  ..addOption('level', abbr: 'l', help: 'Target level: 1 raw, 2 consolidated, 3 concept', mandatory: true);

ArgParser _memoryGraphCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory');

ArgParser _memoryConsolidateCommandParser() => ArgParser()
  ..addOption('output', abbr: 'o', defaultsTo: 'kb', help: 'Knowledge-base directory')
  ..addOption('limit', defaultsTo: '100', help: 'Max records to consolidate')
  ..addOption('provider', defaultsTo: 'openai', help: 'LLM provider: openai, openrouter or ollama')
  ..addOption('api-key', help: 'API key')
  ..addOption('base-url', help: 'Base URL')
  ..addOption('model', help: 'Model name')
  ..addOption('instructions', help: 'Extra instructions for the consolidation agent');

ArgParser _skillCommandParser() => ArgParser()
  ..addOption('format', abbr: 'f', defaultsTo: 'markdown', help: 'Output format: markdown or json');
