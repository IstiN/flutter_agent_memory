import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_agent_memory/flutter_agent_memory.dart';

Future<void> main(List<String> args) async {
  final parser = buildRootParser();
  final results = parser.parse(args);

  if (results['help'] as bool || results.command == null) {
    printAgentMemoryUsage(parser: parser);
    exit(0);
  }

  try {
    switch (results.command!.name) {
      case 'process':
        await _process(results.command!);
      case 'regenerate':
        await _regenerate(results.command!);
      case 'stats':
        await _stats(results.command!);
      case 'search-tags':
        await _searchTags(results.command!);
      case 'search':
        await _search(results.command!);
      case 'memory':
        await _memory(results.command!);
      case 'skill':
        _skill(results.command!);
    }
  } catch (e, st) {
    stderr.writeln('Error: $e');
    if (results.command?.options.contains('verbose') == true &&
        results.command?['verbose'] == true) {
      stderr.writeln(st);
    }
    exit(1);
  }
}

Future<void> _process(ArgResults args) async {
  final inputPath = args['input'] as String;
  final outputPath = args['output'] as String;
  final providerName = args['provider'] as String;
  final verbose = args['verbose'] as bool;

  final loader = InputLoader();
  final inputs = await loader.load(inputPath);
  if (inputs.isEmpty) {
    throw ArgumentError('No supported files found in $inputPath');
  }

  final provider = _createProvider(args, providerName);
  final orchestrator = KBOrchestrator(provider);
  final mode = KBProcessingModeParsing.fromString(args['mode'] as String);

  KBOrchestratorParams paramsFor(InputContent input, String sourceName, {bool? clean}) =>
      KBOrchestratorParams(
        sourceName: sourceName,
        inputText: input.promptText,
        inputImages: input.images ?? const [],
        outputPath: outputPath,
        processingMode: mode,
        analysisExtraInstructions: args['analysis-instructions'] as String? ?? '',
        aggregationExtraInstructions: args['aggregation-instructions'] as String? ?? '',
        qaMappingExtraInstructions: args['qa-mapping-instructions'] as String? ?? '',
        cleanOutput: clean ?? false,
      );

  if (inputs.length == 1) {
    final input = inputs.first;
    final sourceName = (args['source'] as String?) ??
        _deriveSourceName(inputPath == '-' ? 'stdin' : input.sourcePath);

    final result = await orchestrator.run(paramsFor(input, sourceName, clean: args['clean'] as bool));
    _printResult(result, verbose);
  } else {
    // Directory: process each supported file as a separate source.
    for (final input in inputs) {
      final sourceName = _deriveSourceName(input.sourcePath);
      if (verbose) stdout.writeln('Processing $sourceName...');
      final result = await orchestrator.run(paramsFor(input, sourceName));
      _printResult(result, verbose);
    }
  }
}

void _skill(ArgResults args) {
  final format = args['format'] as String;
  stdout.writeln(buildSkillHelp(format: format));
}

Future<void> _regenerate(ArgResults args) async {
  final outputPath = args['output'] as String;
  final sourceName = args['source'] as String;

  // Regeneration does not require an LLM, but the orchestrator needs a provider
  // for its interface. Create a no-op provider that throws on any AI call.
  final orchestrator = KBOrchestrator(_NoOpProvider());
  final result = await orchestrator.regenerateStructureFromExistingFiles(outputPath, sourceName);
  _printResult(result, args['verbose'] as bool);
}

Future<void> _stats(ArgResults args) async {
  final outputPath = args['output'] as String;
  final manager = KBStructureManager();
  manager.generateIndexes(Directory(outputPath));
  stdout.writeln('Statistics regenerated in $outputPath');
}

Future<void> _searchTags(ArgResults args) async {
  final outputPath = args['output'] as String;
  final tags = _splitList(args['tags'] as String);
  final matchAll = !(args['match-any'] as bool);
  final types = _parseEntityTypes(args['type'] as String?);
  final asJson = args['json'] as bool;

  final engine = KBSearchEngine(Directory(outputPath));
  final results = engine.searchByTags(tags, matchAll: matchAll, entityTypes: types);
  _printSearchResults(results, asJson);
}

Future<void> _search(ArgResults args) async {
  final outputPath = args['output'] as String;
  final query = args['query'] as String;
  final matchAll = args['match-all'] as bool;
  final types = _parseEntityTypes(args['type'] as String?);
  final asJson = args['json'] as bool;
  final showTags = args['show-tags'] as bool;

  final provider = _createProvider(args, args['provider'] as String);
  final engine = KBSearchEngine(Directory(outputPath), provider: provider);
  final searchResult = await engine.searchByText(
    query,
    matchAll: matchAll,
    entityTypes: types,
  );

  if (showTags && !asJson) {
    stdout.writeln('Generated tags: ${searchResult.generatedTags.isNotEmpty ? searchResult.generatedTags.join(', ') : 'none'}');
    stdout.writeln();
  }

  _printSearchResults(searchResult.results, asJson);
}

Map<String, dynamic> _searchResultToJson(KBSearchResult r) => {
  'type': r.entityType,
  'id': r.id,
  'path': r.path,
  'matchedTags': r.matchedTags,
};

void _printSearchResults(List<KBSearchResult> results, bool asJson) {
  if (asJson) {
    stdout.writeln(jsonEncode(results.map(_searchResultToJson).toList()));
    return;
  }

  if (results.isEmpty) {
    stdout.writeln('No records found.');
    return;
  }

  stdout.writeln('Found ${results.length} record(s):\n');
  for (final r in results) {
    stdout.writeln('- [${r.entityType}] ${r.id}: ${r.title}');
    stdout.writeln('  path: ${r.path}');
    stdout.writeln('  matched tags: ${r.matchedTags.join(', ')}');
    stdout.writeln();
  }
}

Future<void> _memory(ArgResults args) async {
  final sub = args.command;
  if (sub == null) {
    stderr.writeln('Usage: agent_memory memory <subcommand>');
    exit(1);
  }

  switch (sub.name) {
    case 'add':
      await _memoryAdd(sub);
    case 'ask':
      await _memoryAsk(sub);
    case 'list':
      await _memoryList(sub);
    case 'delete':
      await _memoryDelete(sub);
    case 'rank':
      await _memoryRank(sub);
    case 'update':
      await _memoryUpdate(sub);
    case 'consolidate':
      await _memoryConsolidate(sub);
  }
}

Future<void> _memoryConsolidate(ArgResults args) async {
  final outputPath = args['output'] as String;
  final limit = int.tryParse(args['limit'] as String) ?? 100;
  final extraInstructions = args['instructions'] as String? ?? '';

  final provider = _createProvider(args, args['provider'] as String);
  final store = KBMemoryStore(Directory(outputPath), provider: provider, source: 'agent');
  final result = await store.consolidate(
    extraInstructions: extraInstructions,
    limit: limit,
  );

  stdout.writeln('Consolidated ${result.skills.length} skill(s) into $outputPath/MEMORY.md');
  for (final skill in result.skills) {
    stdout.writeln('  - ${skill.id}: ${skill.title}');
  }
}

Future<void> _memoryAdd(ArgResults args) async {
  final outputPath = args['output'] as String;
  final type = (args['type'] as String).toLowerCase();
  final text = args['text'] as String;
  final author = args['author'] as String;
  final area = args['area'] as String?;
  final topics = _splitList(args['topics'] as String?);
  final tags = _splitList(args['tags'] as String?);
  final importance = double.tryParse(args['importance'] as String) ?? 0.5;

  final provider = _createOptionalProvider(args);
  final store = KBMemoryStore(Directory(outputPath), provider: provider, source: 'agent');

  late final MemoryRecord record;
  switch (type) {
    case 'question':
      record = await store.addQuestion(
        text: text,
        author: author,
        area: area ?? '',
        topics: topics,
        tags: tags,
        importance: importance,
      );
    case 'answer':
      record = await store.addAnswer(
        text: text,
        author: author,
        area: area ?? '',
        topics: topics,
        tags: tags,
        answersQuestion: args['answers-question'] as String?,
        importance: importance,
      );
    case 'note':
      record = await store.addNote(
        text: text,
        author: author,
        area: area ?? '',
        topics: topics,
        tags: tags,
        importance: importance,
      );
    default:
      throw ArgumentError('Unknown type: $type');
  }

  stdout.writeln('Added ${record.entityType} ${record.id}');
}

Future<void> _memoryAsk(ArgResults args) async {
  final outputPath = args['output'] as String;
  final query = args['query'] as String;
  final asJson = args['json'] as bool;
  final asOf = _parseAsOf(args['as-of'] as String?);

  final provider = _createProvider(args, args['provider'] as String);
  final store = KBMemoryStore(Directory(outputPath), provider: provider, source: 'agent');
  final engine = KBSearchEngine(Directory(outputPath), provider: provider);

  var result = await engine.searchByText(query, matchAll: false);
  if (asOf != null) {
    result = KBTextSearchResult(
      generatedTags: result.generatedTags,
      results: result.results.where((r) => _recordKnownAt(r, asOf)).toList(),
    );
  }
  if (result.results.isNotEmpty) {
    final id = result.results.first.id;
    if (id != null && id.isNotEmpty) store.recordAccess(id);
  }

  if (asJson) {
    stdout.writeln(jsonEncode({
      'generatedTags': result.generatedTags,
      'results': result.results.map(_searchResultToJson).toList(),
    }));
    return;
  }

  stdout.writeln('Generated tags: ${result.generatedTags.isNotEmpty ? result.generatedTags.join(', ') : 'none'}\n');
  _printSearchResults(result.results, false);
}

Future<void> _memoryList(ArgResults args) async {
  final outputPath = args['output'] as String;
  final type = args['type'] as String?;
  final tags = _splitList(args['tags'] as String?);
  final sort = args['sort'] as String;
  final limit = args['limit'] != null ? int.tryParse(args['limit'] as String) : null;
  final asJson = args['json'] as bool;
  final asOf = _parseAsOf(args['as-of'] as String?);

  final store = KBMemoryStore(Directory(outputPath), source: 'agent');
  final records = store.list(
    type: type,
    tags: tags.isNotEmpty ? tags : null,
    sortBy: sort,
    limit: limit,
    asOf: asOf,
  );

  _printMemoryRecords(records, asJson, header: 'Found');
}

DateTime? _parseAsOf(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

bool _recordKnownAt(KBSearchResult result, DateTime asOf) {
  final dateStr = result.question?.date ?? result.answer?.date ?? result.note?.date;
  if (dateStr == null || dateStr.isEmpty) return true;
  final dt = DateTime.tryParse(dateStr);
  if (dt == null) return true;
  return !dt.isAfter(asOf);
}

Future<void> _memoryDelete(ArgResults args) async {
  final outputPath = args['output'] as String;
  final id = args['id'] as String;

  final store = KBMemoryStore(Directory(outputPath), source: 'agent');
  store.deleteRecord(id);
  stdout.writeln('Deleted $id');
}

Future<void> _memoryRank(ArgResults args) async {
  final outputPath = args['output'] as String;
  final limit = int.tryParse(args['limit'] as String) ?? 10;
  final sort = args['sort'] as String;
  final asJson = args['json'] as bool;

  final store = KBMemoryStore(Directory(outputPath), source: 'agent');
  final records = store.list(sortBy: sort, limit: limit);

  _printMemoryRecords(records, asJson, header: 'Top');
}

Future<void> _memoryUpdate(ArgResults args) async {
  final outputPath = args['output'] as String;
  final id = args['id'] as String;
  final text = args['text'] as String?;
  final tags = _splitList(args['tags'] as String?);
  final importance = args['importance'] != null ? double.tryParse(args['importance'] as String) : null;

  final provider = _createOptionalProvider(args);
  final store = KBMemoryStore(Directory(outputPath), provider: provider, source: 'agent');
  final record = await store.updateRecord(
    id,
    text: text,
    tags: tags.isNotEmpty ? tags : null,
    importance: importance,
  );
  stdout.writeln('Updated ${record.entityType} ${record.id}');
}

LlmProvider? _createOptionalProvider(ArgResults args) {
  try {
    return _createProvider(args, args['provider'] as String);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _recordToJson(MemoryRecord r) => {
  'type': r.entityType,
  'id': r.id,
  'title': r.title,
  'author': r.author,
  'area': r.area,
  'tags': r.tags,
  'accessCount': r.accessCount,
  'lastAccessedAt': r.lastAccessedAt,
  'importance': r.importance,
  'path': r.path,
};

void _printMemoryRecord(MemoryRecord r) {
  stdout.writeln('- [${r.entityType}] ${r.id}: ${r.title}');
  stdout.writeln('  author: ${r.author}, area: ${r.area}, importance: ${r.importance.toStringAsFixed(2)}');
  stdout.writeln('  accessCount: ${r.accessCount}, lastAccessedAt: ${r.lastAccessedAt ?? 'never'}');
  stdout.writeln('  tags: ${r.tags.join(', ')}');
  stdout.writeln('  path: ${r.path}');
  stdout.writeln();
}

List<String> _splitList(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  return value.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
}

List<String>? _parseEntityTypes(String? value) {
  final list = _splitList(value);
  return list.isEmpty ? null : list.map((t) => t.toLowerCase()).toList();
}

void _printMemoryRecords(List<MemoryRecord> records, bool asJson, {required String header}) {
  if (asJson) {
    stdout.writeln(jsonEncode(records.map(_recordToJson).toList()));
    return;
  }

  if (records.isEmpty) {
    stdout.writeln('No records found.');
    return;
  }

  stdout.writeln('$header ${records.length} record(s):\n');
  for (final r in records) {
    _printMemoryRecord(r);
  }
}

String _deriveSourceName(String inputPath) {
  if (inputPath == '-') return 'stdin';
  final name = File(inputPath).uri.pathSegments.last;
  final dotIndex = name.lastIndexOf('.');
  return dotIndex > 0 ? name.substring(0, dotIndex) : name;
}

LlmProvider _createProvider(ArgResults args, String providerName) {
  String? optionalString(String name) =>
      args.options.contains(name) ? args[name] as String? : null;
  int? optionalInt(String name) =>
      args.options.contains(name) && args[name] != null ? int.tryParse(args[name] as String) : null;
  double? optionalDouble(String name) =>
      args.options.contains(name) && args[name] != null ? double.tryParse(args[name] as String) : null;

  final config = LlmConfig.fromEnvironment(
    provider: providerName,
    apiKey: optionalString('api-key'),
    baseUrl: optionalString('base-url'),
    model: optionalString('model'),
    maxTokens: optionalInt('max-tokens'),
    temperature: optionalDouble('temperature'),
  );

  if (!config.isConfigured) {
    throw StateError(
      'Provider is not configured. Set environment variables for $providerName '
      'or pass --api-key and --model.',
    );
  }

  return ProviderFactory.create(config);
}

void _printResult(KBResult result, bool verbose) {
  stdout.writeln('Success: ${result.success}');
  stdout.writeln(result.message);
  if (verbose) {
    stdout.writeln('Questions: ${result.questionsCount}');
    stdout.writeln('Answers: ${result.answersCount}');
    stdout.writeln('Notes: ${result.notesCount}');
    stdout.writeln('People: ${result.peopleCount}');
    stdout.writeln('Topics: ${result.topicsCount}');
    stdout.writeln('Areas: ${result.areasCount}');
  }
}

class _NoOpProvider implements LlmProvider {
  @override
  String get defaultModel => '';

  @override
  Future<String> chat(String prompt, {String? model}) async =>
      throw UnsupportedError('Regeneration does not use LLM calls');

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) async =>
      throw UnsupportedError('Regeneration does not use LLM calls');
}
