import 'dart:io';

import '../agents/kb_consolidation_agent.dart';
import '../agents/kb_tag_generator_agent.dart';
import '../llm/llm_provider.dart';
import '../models/analysis_result.dart';
import '../models/answer.dart';
import '../models/consolidation_result.dart';
import '../models/kb_context.dart';
import '../models/note.dart';
import '../models/question.dart';
import '../utils/date_utils.dart';
import '../utils/frontmatter.dart';
import '../utils/slugify.dart';
import 'kb_context_loader.dart';
import 'kb_file_parser.dart';
import 'kb_structure_builder.dart';

/// Persistent agent memory store backed by Markdown files.
///
/// Provides CRUD operations for questions, answers, and notes, plus access
/// tracking (last used, access count) that feeds into search ranking.
class KBMemoryStore {
  final Directory kbDir;
  final LlmProvider? provider;
  final String source;
  final KBStructureBuilder _builder;
  final KBFileParser _parser;
  final KBContextLoader _contextLoader;

  KBMemoryStore(
    this.kbDir, {
    this.provider,
    this.source = 'agent',
  })  : _builder = KBStructureBuilder(),
        _parser = KBFileParser(),
        _contextLoader = KBContextLoader();

  /// Adds a new question to the memory store.
  Future<MemoryRecord> addQuestion({
    required String text,
    String author = 'agent',
    String? area,
    List<String>? topics,
    List<String>? tags,
    String? answeredBy,
    double importance = 0.5,
  }) async {
    final prepared = await _prepareAdd(
      text,
      area: area,
      topics: topics,
      tags: tags,
      prefix: 'q',
      nextId: _loadContext().nextQuestionId,
    );

    final question = Question(
      id: prepared.id,
      author: author,
      text: text,
      date: prepared.now,
      area: prepared.enriched.area,
      topics: prepared.enriched.topics,
      tags: prepared.enriched.tags,
      answeredBy: answeredBy,
      links: const [],
      importance: importance,
    );

    _builder.buildQuestionFile(question, kbDir, source, const AnalysisResult(questions: [], answers: [], notes: []));
    return _toRecord(question: question);
  }

  /// Adds a new answer to the memory store.
  Future<MemoryRecord> addAnswer({
    required String text,
    String author = 'agent',
    String? area,
    List<String>? topics,
    List<String>? tags,
    String? answersQuestion,
    double quality = 0.8,
    double importance = 0.5,
  }) async {
    final prepared = await _prepareAdd(
      text,
      area: area,
      topics: topics,
      tags: tags,
      prefix: 'a',
      nextId: _loadContext().nextAnswerId,
    );

    final answer = Answer(
      id: prepared.id,
      author: author,
      text: text,
      date: prepared.now,
      area: prepared.enriched.area,
      topics: prepared.enriched.topics,
      tags: prepared.enriched.tags,
      answersQuestion: answersQuestion,
      quality: quality,
      links: const [],
      importance: importance,
    );

    _builder.buildAnswerFile(answer, kbDir, source);
    return _toRecord(answer: answer);
  }

  /// Adds a new note to the memory store.
  Future<MemoryRecord> addNote({
    required String text,
    String author = 'agent',
    String? area,
    List<String>? topics,
    List<String>? tags,
    List<String>? answersQuestions,
    double importance = 0.5,
  }) async {
    final prepared = await _prepareAdd(
      text,
      area: area,
      topics: topics,
      tags: tags,
      prefix: 'n',
      nextId: _loadContext().nextNoteId,
    );

    final note = Note(
      id: prepared.id,
      text: text,
      area: prepared.enriched.area,
      topics: prepared.enriched.topics,
      tags: prepared.enriched.tags,
      author: author,
      date: prepared.now,
      answersQuestions: answersQuestions ?? const [],
      links: const [],
      importance: importance,
    );

    _builder.buildNoteFile(note, kbDir, source);
    return _toRecord(note: note);
  }

  /// Deletes a record by id.
  void deleteRecord(String id) {
    final record = findById(id);
    if (record == null) return;
    final file = File(record.path);
    if (file.existsSync()) file.deleteSync();
  }

  /// Updates the text and/or tags of an existing record.
  Future<MemoryRecord> updateRecord(
    String id, {
    String? text,
    List<String>? tags,
    double? importance,
  }) async {
    final record = findById(id);
    if (record == null) throw ArgumentError('Record not found: $id');

    switch (record.entityType) {
      case 'question':
        final q = record.question!;
        final updatedTags = tags ?? q.tags;
        final updatedText = text ?? q.text;
        final enriched = await _enrich(updatedText, area: q.area, topics: q.topics, tags: updatedTags);
        final updated = q.copyWith(
          text: updatedText,
          tags: enriched.tags,
          topics: enriched.topics,
          area: enriched.area,
          importance: importance ?? q.importance,
        );
        _builder.buildQuestionFile(updated, kbDir, source, const AnalysisResult(questions: [], answers: [], notes: []));
        return _toRecord(question: updated);
      case 'answer':
        final a = record.answer!;
        final updatedTags = tags ?? a.tags;
        final updatedText = text ?? a.text;
        final enriched = await _enrich(updatedText, area: a.area, topics: a.topics, tags: updatedTags);
        final updated = a.copyWith(
          text: updatedText,
          tags: enriched.tags,
          topics: enriched.topics,
          area: enriched.area,
          importance: importance ?? a.importance,
        );
        _builder.buildAnswerFile(updated, kbDir, source);
        return _toRecord(answer: updated);
      case 'note':
        final n = record.note!;
        final updatedTags = tags ?? n.tags;
        final updatedText = text ?? n.text;
        final enriched = await _enrich(updatedText, area: n.area, topics: n.topics, tags: updatedTags);
        final updated = n.copyWith(
          text: updatedText,
          tags: enriched.tags,
          topics: enriched.topics,
          area: enriched.area,
          importance: importance ?? n.importance,
        );
        _builder.buildNoteFile(updated, kbDir, source);
        return _toRecord(note: updated);
      default:
        throw UnsupportedError('Unsupported entity type: ${record.entityType}');
    }
  }

  /// Records that a record was accessed, incrementing its counter.
  void recordAccess(String id) {
    final record = findById(id);
    if (record == null) return;

    final now = currentUtcTimestamp();
    switch (record.entityType) {
      case 'question':
        final updated = record.question!.copyWith(
          accessCount: record.question!.accessCount + 1,
          lastAccessedAt: now,
        );
        _builder.buildQuestionFile(updated, kbDir, source, const AnalysisResult(questions: [], answers: [], notes: []));
      case 'answer':
        final updated = record.answer!.copyWith(
          accessCount: record.answer!.accessCount + 1,
          lastAccessedAt: now,
        );
        _builder.buildAnswerFile(updated, kbDir, source);
      case 'note':
        final updated = record.note!.copyWith(
          accessCount: record.note!.accessCount + 1,
          lastAccessedAt: now,
        );
        _builder.buildNoteFile(updated, kbDir, source);
    }
  }

  /// Finds a single record by id.
  MemoryRecord? findById(String id) {
    final lowerId = id.toLowerCase();
    final dirs = {
      'q': Directory('${kbDir.path}/questions'),
      'a': Directory('${kbDir.path}/answers'),
      'n': Directory('${kbDir.path}/notes'),
    };

    for (final entry in dirs.entries) {
      if (!lowerId.startsWith(entry.key)) continue;
      final file = File('${entry.value.path}/$id.md');
      if (!file.existsSync()) continue;
      try {
        return _parseFile(file);
      } catch (_) {}
    }
    return null;
  }

  /// Lists records, optionally filtered and sorted.
  List<MemoryRecord> list({
    String? type,
    List<String>? tags,
    String sortBy = 'lastAccessed',
    int? limit,
  }) {
    final records = <MemoryRecord>[];
    final types = type != null ? [type.toLowerCase()] : ['question', 'answer', 'note'];

    for (final t in types) {
      final dirName = t == 'question' ? 'questions' : t == 'answer' ? 'answers' : 'notes';
      final dir = Directory('${kbDir.path}/$dirName');
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final record = _parseFile(file);
          if (tags != null && tags.isNotEmpty) {
            final normalizedRecordTags = record.tags.map((x) => x.toLowerCase()).toSet();
            final normalizedRequested = tags.map((x) => x.toLowerCase()).toSet();
            if (!normalizedRequested.any(normalizedRecordTags.contains)) continue;
          }
          records.add(record);
        } catch (_) {}
      }
    }

    switch (sortBy) {
      case 'accessCount':
        records.sort((a, b) => b.accessCount.compareTo(a.accessCount));
      case 'importance':
        records.sort((a, b) => b.importance.compareTo(a.importance));
      case 'lastAccessed':
      default:
        records.sort((a, b) {
          final aDate = a.lastAccessedAt ?? a.date;
          final bDate = b.lastAccessedAt ?? b.date;
          return bDate.compareTo(aDate);
        });
    }

    if (limit != null && records.length > limit) {
      return records.sublist(0, limit);
    }
    return records;
  }

  Future<({String id, String now, _Enriched enriched})> _prepareAdd(
    String text, {
    String? area,
    List<String>? topics,
    List<String>? tags,
    required String prefix,
    required int Function() nextId,
  }) async {
    final enriched = await _enrich(
      text,
      area: area,
      topics: topics ?? const [],
      tags: tags ?? const [],
    );
    final id = '${prefix}_${_pad(nextId())}';
    final now = currentUtcTimestamp();
    return (id: id, now: now, enriched: enriched);
  }

  Future<_Enriched> _enrich(
    String text, {
    String? area,
    List<String>? topics,
    List<String>? tags,
  }) async {
    var resolvedArea = area != null && area.isNotEmpty ? area : 'general';
    var resolvedTopics = topics != null && topics.isNotEmpty ? topics : <String>[];
    var resolvedTags = tags != null && tags.isNotEmpty ? tags : <String>[];

    if (provider != null && (resolvedArea == 'general' || resolvedTags.isEmpty)) {
      final generator = KBTagGeneratorAgent(provider!);
      final generated = await generator.generateTags(text, maxTags: 5);
      if (resolvedTags.isEmpty) resolvedTags = generated;
      if (resolvedTopics.isEmpty && generated.isNotEmpty) {
        resolvedTopics = [slugify(generated.first)];
      }
      if (resolvedArea == 'general' && generated.isNotEmpty) {
        resolvedArea = _guessArea(generated);
      }
    }

    return _Enriched(
      area: resolvedArea,
      topics: resolvedTopics,
      tags: resolvedTags,
    );
  }

  String _guessArea(List<String> tags) {
    final lowered = tags.map((t) => t.toLowerCase()).toSet();
    final areaHints = <String, List<String>>{
      'development': ['dart', 'flutter', 'test', 'testing', 'unit-tests', 'riverpod', 'bloc'],
      'infrastructure': ['docker', 'kubernetes', 'ci/cd', 'github-actions', 'deploy'],
      'security': ['auth', 'security', 'oauth', 'jwt'],
      'business': ['product', 'requirements', 'meeting'],
    };
    for (final entry in areaHints.entries) {
      if (entry.value.any(lowered.contains)) return entry.key;
    }
    return 'general';
  }

  KBContext _loadContext() => _contextLoader.loadContext(kbDir);

  MemoryRecord _parseFile(File file) {
    final content = file.readAsStringSync();
    final fm = parseFrontmatter(content);
    final type = fm.getString('type') ?? '';

    switch (type) {
      case 'question':
        final q = _parser.parseQuestion(content);
        return _toRecord(question: q, path: file.path);
      case 'answer':
        final a = _parser.parseAnswer(content);
        return _toRecord(answer: a, path: file.path);
      case 'note':
        final n = _parser.parseNote(content);
        return _toRecord(note: n, path: file.path);
      default:
        throw FormatException('Unknown record type: $type');
    }
  }

  MemoryRecord _toRecord({
    Question? question,
    Answer? answer,
    Note? note,
    String? path,
  }) {
    if (question != null) {
      final filePath = path ?? '${kbDir.path}/questions/${question.id}.md';
      final parsed = _tryParseQuestion(File(filePath)) ?? question;
      return MemoryRecord(
        entityType: 'question',
        path: filePath,
        question: parsed,
        accessCount: parsed.accessCount,
        lastAccessedAt: parsed.lastAccessedAt,
        importance: parsed.importance,
      );
    }
    if (answer != null) {
      final filePath = path ?? '${kbDir.path}/answers/${answer.id}.md';
      final parsed = _tryParseAnswer(File(filePath)) ?? answer;
      return MemoryRecord(
        entityType: 'answer',
        path: filePath,
        answer: parsed,
        accessCount: parsed.accessCount,
        lastAccessedAt: parsed.lastAccessedAt,
        importance: parsed.importance,
      );
    }
    if (note != null) {
      final filePath = path ?? '${kbDir.path}/notes/${note.id}.md';
      final parsed = _tryParseNote(File(filePath)) ?? note;
      return MemoryRecord(
        entityType: 'note',
        path: filePath,
        note: parsed,
        accessCount: parsed.accessCount,
        lastAccessedAt: parsed.lastAccessedAt,
        importance: parsed.importance,
      );
    }
    throw ArgumentError('At least one entity must be provided');
  }

  Question? _tryParseQuestion(File file) {
    try {
      if (!file.existsSync()) return null;
      return _parser.parseQuestion(file.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  Answer? _tryParseAnswer(File file) {
    try {
      if (!file.existsSync()) return null;
      return _parser.parseAnswer(file.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  Note? _tryParseNote(File file) {
    try {
      if (!file.existsSync()) return null;
      return _parser.parseNote(file.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  /// Consolidates the top [limit] memory records into a high-level summary and
  /// reusable skill cards using an LLM.
  Future<ConsolidationResult> consolidate({
    String extraInstructions = '',
    int limit = 100,
  }) async {
    if (provider == null) {
      throw StateError('An LLM provider is required for consolidation.');
    }

    final agent = KBConsolidationAgent(provider!);
    final records = list(limit: limit);
    final existingSummary = _readExistingSummary();

    final result = await agent.consolidate(
      records,
      existingSummary: existingSummary,
      extraInstructions: extraInstructions,
    );

    _writeConsolidation(result);
    return result;
  }

  String? _readExistingSummary() {
    final file = File('${kbDir.path}/MEMORY.md');
    if (!file.existsSync()) return null;
    final text = file.readAsStringSync().trim();
    return text.isEmpty ? null : text;
  }

  void _writeConsolidation(ConsolidationResult result) {
    final memoryFile = File('${kbDir.path}/MEMORY.md');
    memoryFile.writeAsStringSync(result.summary);

    final skillsDir = Directory('${kbDir.path}/skills');
    if (result.skills.isEmpty) {
      if (skillsDir.existsSync()) {
        for (final f in skillsDir.listSync().whereType<File>()) {
          f.deleteSync();
        }
      }
      return;
    }

    skillsDir.createSync(recursive: true);
    for (var i = 0; i < result.skills.length; i++) {
      final skill = result.skills[i];
      final id = 'sk_${(i + 1).toString().padLeft(4, '0')}';
      final file = File('${skillsDir.path}/$id.md');
      final buffer = StringBuffer()
        ..writeln('---')
        ..writeln('id: $id')
        ..writeln('title: ${skill.title}')
        ..writeln('tags: ${skill.tags.join(', ')}')
        ..writeln('---')
        ..writeln()
        ..writeln(skill.instruction);
      file.writeAsStringSync(buffer.toString());
    }
  }

  String _pad(int value) => value.toString().padLeft(4, '0');
}

class _Enriched {
  final String area;
  final List<String> topics;
  final List<String> tags;

  _Enriched({required this.area, required this.topics, required this.tags});
}

/// A unified view of a knowledge-base record used by the memory store.
class MemoryRecord {
  final String entityType;
  final String path;
  final Question? question;
  final Answer? answer;
  final Note? note;
  final int accessCount;
  final String? lastAccessedAt;
  final double importance;

  const MemoryRecord({
    required this.entityType,
    required this.path,
    this.question,
    this.answer,
    this.note,
    this.accessCount = 0,
    this.lastAccessedAt,
    this.importance = 0.5,
  });

  String get id => question?.id ?? answer?.id ?? note?.id ?? '';

  String get title => question?.text ?? answer?.text ?? note?.text ?? '';

  String get text => title;

  String get author => question?.author ?? answer?.author ?? note?.author ?? '';

  String get date => question?.date ?? answer?.date ?? note?.date ?? '';

  List<String> get tags => question?.tags ?? answer?.tags ?? note?.tags ?? const [];

  String get area => question?.area ?? answer?.area ?? note?.area ?? '';
}
