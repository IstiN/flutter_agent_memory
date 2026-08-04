import '../agents/kb_consolidation_agent.dart';
import '../agents/kb_secret_redaction_agent.dart';
import '../agents/kb_tag_generator_agent.dart';
import '../llm/llm_provider.dart';
import '../models/answer.dart';
import '../models/consolidation_result.dart';
import '../models/memory_level.dart';
import '../models/memory_type.dart';
import '../models/note.dart';
import '../models/question.dart';
import '../models/relation.dart';
import '../utils/date_utils.dart';
import '../utils/memory_utils.dart';
import '../utils/slugify.dart';
import 'file_kb_storage_factory.dart'
    if (dart.library.html) 'file_kb_storage_factory_stub.dart';

export '../utils/memory_utils.dart';
import 'kb_file_parser.dart';
import 'kb_graph_builder.dart';
import 'kb_markdown_renderer.dart';
import 'kb_storage.dart';
import 'memory/memory_consolidation_writer.dart';
import 'memory/memory_dedup_service.dart';
import 'memory/memory_level_service.dart';
import 'memory/memory_provenance_service.dart';
import 'memory/memory_revision_service.dart';

export 'memory/memory_consolidation_writer.dart';
export 'memory/memory_dedup_service.dart';
export 'memory/memory_level_service.dart';
export 'memory/memory_provenance_service.dart';
export 'memory/memory_revision_service.dart';

/// Agent memory store backed by a pluggable [KbStorage] backend.
///
/// Provides CRUD operations for questions, answers, and notes, plus access
/// tracking (last used, access count) that feeds into search ranking.
///
/// The default constructor accepts any [KbStorage] implementation. Use
/// [KBMemoryStore.file] for the classic Markdown file backend.
class KBMemoryStore {
  final KbStorage storage;
  final LlmProvider? provider;
  final String source;

  /// If true, capture methods skip notes/answers/questions whose normalized
  /// text already exists in storage. Defaults to true.
  final bool deduplicateOnCapture;

  /// Optional configuration for automatic memory-level promotion.
  final MemoryPromotionPolicy promotionPolicy;

  final KBFileParser _parser;
  final KbMarkdownRenderer _renderer;
  late final MemoryDedupService _dedup;
  late final MemoryRevisionService _revision;
  late final MemoryLevelService _levels;
  late final MemoryConsolidationWriter _consolidationWriter;

  KBMemoryStore(
    this.storage, {
    this.provider,
    this.source = 'agent',
    this.deduplicateOnCapture = true,
    this.promotionPolicy = const MemoryPromotionPolicy(),
  }) : _parser = KBFileParser(),
       _renderer = const KbMarkdownRenderer() {
    _dedup = MemoryDedupService(storage, _parser);
    _revision = MemoryRevisionService(storage);
    _consolidationWriter = MemoryConsolidationWriter(storage, _revision);
    _levels = MemoryLevelService(
      storage: storage,
      policy: promotionPolicy,
      deleteRecord: deleteRecord,
      writeNote: _writeNote,
      listNotes: () async {
        final records = await list(type: 'note', limit: null);
        return records.map((r) => r.note).whereType<Note>().toList();
      },
    );
  }

  /// Creates a store backed by the file-system Markdown directory layout.
  factory KBMemoryStore.file(
    dynamic kbDir, {
    LlmProvider? provider,
    String source = 'agent',
    bool deduplicateOnCapture = true,
    MemoryPromotionPolicy promotionPolicy = const MemoryPromotionPolicy(),
  }) {
    return KBMemoryStore(
      createFileKbStorage(kbDir),
      provider: provider,
      source: source,
      deduplicateOnCapture: deduplicateOnCapture,
      promotionPolicy: promotionPolicy,
    );
  }

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
    final context = await storage.loadContext();
    final prepared = await _prepareAdd(
      text,
      area: area,
      topics: topics,
      tags: tags,
      prefix: 'q',
      nextId: context.nextQuestionId(),
    );

    final question = Question(
      id: prepared.id,
      author: author,
      text: prepared.text,
      date: prepared.now,
      area: prepared.enriched.area,
      topics: prepared.enriched.topics,
      tags: prepared.enriched.tags,
      answeredBy: answeredBy,
      links: const [],
      importance: importance,
    );

    if (deduplicateOnCapture && await _dedup.hasDuplicateQuestion(question.text)) {
      return _toRecord(question: question);
    }

    await _writeQuestion(question);
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
    final context = await storage.loadContext();
    final prepared = await _prepareAdd(
      text,
      area: area,
      topics: topics,
      tags: tags,
      prefix: 'a',
      nextId: context.nextAnswerId(),
    );

    final answer = Answer(
      id: prepared.id,
      author: author,
      text: prepared.text,
      date: prepared.now,
      area: prepared.enriched.area,
      topics: prepared.enriched.topics,
      tags: prepared.enriched.tags,
      answersQuestion: answersQuestion,
      quality: quality,
      links: const [],
      importance: importance,
    );

    if (deduplicateOnCapture && await _dedup.hasDuplicateAnswer(answer.text)) {
      return _toRecord(answer: answer);
    }

    await _writeAnswer(answer);
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
    String? memoryType,
    String? validFrom,
    String? validUntil,
    int? level,
    List<Relation>? relations,
  }) async {
    final context = await storage.loadContext();
    final prepared = await _prepareAdd(
      text,
      area: area,
      topics: topics,
      tags: tags,
      prefix: 'n',
      nextId: context.nextNoteId(),
    );

    final note = Note(
      id: prepared.id,
      text: prepared.text,
      area: prepared.enriched.area,
      topics: prepared.enriched.topics,
      tags: prepared.enriched.tags,
      author: author,
      date: prepared.now,
      answersQuestions: answersQuestions ?? const [],
      links: const [],
      importance: importance,
      memoryType: MemoryType.normalize(memoryType),
      validFrom: validFrom,
      validUntil: validUntil,
      level: MemoryLevel.normalize(level),
      relations: relations ?? const [],
    );

    if (deduplicateOnCapture && await _dedup.hasDuplicateNote(note)) {
      return _toRecord(note: note);
    }

    await _writeNote(note);
    return _toRecord(note: note);
  }

  /// Deletes a record by id.
  Future<void> deleteRecord(String id) async {
    final type = _typeFromId(id);
    if (type == null) return;
    await storage.deleteEntity(type, id);
  }

  /// Updates the text and/or tags of an existing record.
  Future<MemoryRecord> updateRecord(
    String id, {
    String? text,
    List<String>? tags,
    double? importance,
    String? memoryType,
    String? validFrom,
    String? validUntil,
    int? level,
    List<Relation>? relations,
  }) async {
    final record = await findById(id);
    if (record == null) throw ArgumentError('Record not found: $id');

    return switch (record.entityType) {
      'question' => _updateQuestion(record.question!, text: text, tags: tags, importance: importance),
      'answer' => _updateAnswer(record.answer!, text: text, tags: tags, importance: importance),
      'note' => _updateNote(
          record.note!,
          text: text,
          tags: tags,
          importance: importance,
          memoryType: memoryType,
          validFrom: validFrom,
          validUntil: validUntil,
          level: level,
          relations: relations,
        ),
      _ => throw UnsupportedError('Unsupported entity type: ${record.entityType}'),
    };
  }

  Future<MemoryRecord> _updateQuestion(
    Question q, {
    String? text,
    List<String>? tags,
    double? importance,
  }) async {
    final updated = await _updateEntity(
      text ?? q.text,
      q.area,
      q.topics,
      tags ?? q.tags,
      '#question',
      importance ?? q.importance,
    );
    final next = q.copyWith(
      text: updated.text,
      tags: updated.tags,
      topics: updated.topics,
      area: updated.area,
      importance: updated.importance,
    );
    await _writeQuestion(next);
    return _toRecord(question: next);
  }

  Future<MemoryRecord> _updateAnswer(
    Answer a, {
    String? text,
    List<String>? tags,
    double? importance,
  }) async {
    final updated = await _updateEntity(
      text ?? a.text,
      a.area,
      a.topics,
      tags ?? a.tags,
      '#answer',
      importance ?? a.importance,
    );
    final next = a.copyWith(
      text: updated.text,
      tags: updated.tags,
      topics: updated.topics,
      area: updated.area,
      importance: updated.importance,
    );
    await _writeAnswer(next);
    return _toRecord(answer: next);
  }

  Future<MemoryRecord> _updateNote(
    Note n, {
    String? text,
    List<String>? tags,
    double? importance,
    String? memoryType,
    String? validFrom,
    String? validUntil,
    int? level,
    List<Relation>? relations,
  }) async {
    final updated = await _updateEntity(
      text ?? n.text,
      n.area,
      n.topics,
      tags ?? n.tags,
      '#note',
      importance ?? n.importance,
    );
    final next = n.copyWith(
      text: updated.text,
      tags: updated.tags,
      topics: updated.topics,
      area: updated.area,
      importance: updated.importance,
      memoryType: memoryType != null
          ? MemoryType.normalize(memoryType)
          : n.memoryType,
      validFrom: validFrom ?? n.validFrom,
      validUntil: validUntil ?? n.validUntil,
      level: level != null ? MemoryLevel.normalize(level) : n.level,
      relations: relations ?? n.relations,
    );
    await _writeNote(next);
    return _toRecord(note: next);
  }

  Future<({String text, List<String> tags, List<String> topics, String area, double importance})>
  _updateEntity(
    String originalText,
    String area,
    List<String> topics,
    List<String> tags,
    String entityTag,
    double importance,
  ) async {
    final updatedText = KBSecretRedactionAgent.redact(originalText);
    final mergedTags = _renderer.buildEntityTags(tags, source, entityTag);
    final enriched = await _enrich(
      updatedText,
      area: area.isNotEmpty ? area : null,
      topics: topics,
      tags: mergedTags,
    );
    return (
      text: updatedText,
      tags: enriched.tags,
      topics: enriched.topics,
      area: enriched.area,
      importance: importance,
    );
  }

  /// Records that a record was accessed, incrementing its counter.
  Future<void> recordAccess(String id) async {
    final record = await findById(id);
    if (record == null) return;

    final now = currentUtcTimestamp();
    switch (record.entityType) {
      case 'question':
        final updated = record.question!.copyWith(
          accessCount: record.question!.accessCount + 1,
          lastAccessedAt: now,
        );
        await _writeQuestion(updated);
      case 'answer':
        final updated = record.answer!.copyWith(
          accessCount: record.answer!.accessCount + 1,
          lastAccessedAt: now,
        );
        await _writeAnswer(updated);
      case 'note':
        final updated = record.note!.copyWith(
          accessCount: record.note!.accessCount + 1,
          lastAccessedAt: now,
        );
        await _writeNote(updated);
    }
  }

  /// Finds a single record by id.
  Future<MemoryRecord?> findById(String id) async {
    final type = _typeFromId(id);
    if (type == null) return null;
    final content = await storage.readEntity(type, id);
    if (content == null) return null;
    try {
      return _parseContent(type, content);
    } catch (_) {
      return null;
    }
  }

  /// Lists records, optionally filtered and sorted.
  ///
  /// [asOf] returns only records whose [date] is on or before the given time,
  /// useful for answering "what did I know at date X?".
  Future<List<MemoryRecord>> list({
    String? type,
    List<String>? tags,
    String sortBy = 'lastAccessed',
    int? limit,
    DateTime? asOf,
  }) async {
    final records = <MemoryRecord>[];
    final types = type != null
        ? [type.toLowerCase()]
        : ['question', 'answer', 'note'];

    for (final t in types) {
      for (final id in await storage.listEntityIds(t)) {
        try {
          final content = await storage.readEntity(t, id);
          if (content == null) continue;
          final record = _parseContent(t, content);
          if (tags != null && tags.isNotEmpty) {
            final normalizedRecordTags = record.tags
                .map((x) => x.toLowerCase())
                .toSet();
            final normalizedRequested = tags
                .map((x) => x.toLowerCase())
                .toSet();
            if (!normalizedRequested.any(normalizedRecordTags.contains))
              continue;
          }
          if (asOf != null && !_isRecordActiveAt(record, asOf)) continue;
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

  Future<({String id, String text, String now, _Enriched enriched})>
  _prepareAdd(
    String text, {
    String? area,
    List<String>? topics,
    List<String>? tags,
    required String prefix,
    required int nextId,
  }) async {
    final safeText = KBSecretRedactionAgent.redact(text);
    final enriched = await _enrich(
      safeText,
      area: area,
      topics: topics ?? const [],
      tags: tags ?? const [],
    );
    final id = '${prefix}_${_pad(nextId)}';
    final now = currentUtcTimestamp();
    return (id: id, text: safeText, now: now, enriched: enriched);
  }

  Future<_Enriched> _enrich(
    String text, {
    String? area,
    List<String>? topics,
    List<String>? tags,
  }) async {
    var resolvedArea = _nonEmpty(area) ?? 'general';
    var resolvedTopics = topics ?? const <String>[];
    var resolvedTags = tags ?? const <String>[];

    if (provider != null &&
        (resolvedArea == 'general' || resolvedTags.isEmpty)) {
      final generated = await KBTagGeneratorAgent(provider!).generateTags(
        text,
        maxTags: 5,
      );
      resolvedTags = resolvedTags.isEmpty ? generated : resolvedTags;
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

  String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String _guessArea(List<String> tags) {
    final lowered = tags.map((t) => t.toLowerCase()).toSet();
    final areaHints = <String, List<String>>{
      'development': [
        'dart',
        'flutter',
        'test',
        'testing',
        'unit-tests',
        'riverpod',
        'bloc',
      ],
      'infrastructure': [
        'docker',
        'kubernetes',
        'ci/cd',
        'github-actions',
        'deploy',
      ],
      'security': ['auth', 'security', 'oauth', 'jwt'],
      'business': ['product', 'requirements', 'meeting'],
    };
    for (final entry in areaHints.entries) {
      if (entry.value.any(lowered.contains)) return entry.key;
    }
    return 'general';
  }

  MemoryRecord _parseContent(String type, String content) {
    switch (type) {
      case 'question':
        final q = _parser.parseQuestion(content);
        return _toRecord(question: q);
      case 'answer':
        final a = _parser.parseAnswer(content);
        return _toRecord(answer: a);
      case 'note':
        final n = _parser.parseNote(content);
        return _toRecord(note: n);
      default:
        throw FormatException('Unknown record type: $type');
    }
  }

  MemoryRecord _toRecord({Question? question, Answer? answer, Note? note}) {
    if (question != null) {
      return MemoryRecord(
        entityType: 'question',
        path: storage.describeLocation('question', question.id),
        question: question,
        accessCount: question.accessCount,
        lastAccessedAt: question.lastAccessedAt,
        importance: question.importance,
      );
    }
    if (answer != null) {
      return MemoryRecord(
        entityType: 'answer',
        path: storage.describeLocation('answer', answer.id),
        answer: answer,
        accessCount: answer.accessCount,
        lastAccessedAt: answer.lastAccessedAt,
        importance: answer.importance,
      );
    }
    if (note != null) {
      return MemoryRecord(
        entityType: 'note',
        path: storage.describeLocation('note', note.id),
        note: note,
        accessCount: note.accessCount,
        lastAccessedAt: note.lastAccessedAt,
        importance: note.importance,
      );
    }
    throw ArgumentError('At least one entity must be provided');
  }

  Future<void> _writeQuestion(Question q) async {
    await storage.writeEntity(
      'question',
      q.id,
      _renderer.renderQuestion(q, source),
    );
  }

  Future<void> _writeAnswer(Answer a) async {
    await storage.writeEntity(
      'answer',
      a.id,
      _renderer.renderAnswer(a, source),
    );
  }

  Future<void> _writeNote(Note n) async {
    await storage.writeEntity('note', n.id, _renderer.renderNote(n, source));
  }

  String? _typeFromId(String id) {
    final lower = id.toLowerCase();
    if (lower.startsWith('q_')) return 'question';
    if (lower.startsWith('a_')) return 'answer';
    if (lower.startsWith('n_')) return 'note';
    return null;
  }

  /// Adds a typed relation from [sourceId] to [targetId].
  ///
  /// Currently supports notes as the source entity.
  Future<MemoryRecord> addRelation(
    String sourceId,
    String targetId,
    String type, {
    double weight = 1.0,
  }) async {
    final record = await findById(sourceId);
    if (record == null)
      throw ArgumentError('Source record not found: $sourceId');
    if (record.note == null)
      throw ArgumentError(
        'Relations are currently supported only for notes: $sourceId',
      );

    final normalizedType = RelationType.normalize(type);
    final existing = record.note!.relations.where(
      (r) => r.target == targetId && r.type == normalizedType,
    );
    if (existing.isNotEmpty) return record;

    final updated = record.note!.copyWith(
      relations: [
        ...record.note!.relations,
        Relation(
          source: sourceId,
          target: targetId,
          type: normalizedType,
          weight: weight,
        ),
      ],
    );
    await _writeNote(updated);
    return _toRecord(note: updated);
  }

  /// Promotes a note to a higher memory level (1 raw → 2 consolidated → 3 concept).
  Future<MemoryRecord> promote(String id, int targetLevel) async {
    final record = await findById(id);
    if (record == null) throw ArgumentError('Record not found: $id');
    if (record.note == null)
      throw ArgumentError(
        'Promotion is currently supported only for notes: $id',
      );

    final newLevel = MemoryLevel.normalize(targetLevel);
    if (newLevel <= record.note!.level) {
      throw ArgumentError(
        'Target level $targetLevel is not higher than current level ${record.note!.level}',
      );
    }

    final updated = record.note!.copyWith(level: newLevel);
    await _writeNote(updated);
    return _toRecord(note: updated);
  }

  /// Regenerates `GRAPH.md` from the current knowledge base.
  Future<void> buildGraph() async {
    await KBGraphBuilder(storage).build();
  }

  /// Reads the current [MEMORY.md] file and returns its revision hash along
  /// with the content.
  Future<MemoryRevision> readMemoryRevision() => _revision.read();

  /// Writes [content] to [MEMORY.md] only if the current revision matches
  /// [expectedHash]. Returns true when the write succeeded, false if the file
  /// was modified concurrently.
  Future<bool> writeMemoryRevision(
    String content,
    String expectedHash,
  ) =>
      _revision.write(content, expectedHash);

  /// Consolidates the top [limit] memory records into a high-level summary and
  /// reusable skill cards using an LLM.
  ///
  /// If [expectedRevisionHash] is provided, the write is conditional on the
  /// existing MEMORY.md still matching that hash.
  Future<ConsolidationResult> consolidate({
    String extraInstructions = '',
    int limit = 100,
    String? expectedRevisionHash,
  }) async {
    if (provider == null) {
      throw StateError('An LLM provider is required for consolidation.');
    }

    final agent = KBConsolidationAgent(provider!);
    final records = await list(limit: limit);
    final existingSummary = await _readExistingSummary();

    final result = await agent.consolidate(
      records,
      existingSummary: existingSummary,
      extraInstructions: extraInstructions,
    );

    await _consolidationWriter.write(
      result,
      expectedRevisionHash: expectedRevisionHash,
    );
    return result;
  }

  Future<String?> _readExistingSummary() async {
    return (await storage.readFile('MEMORY.md'))?.trim();
  }

  bool _isRecordActiveAt(MemoryRecord record, DateTime asOf) {
    final note = record.note;
    if (note != null) {
      return _isNoteActiveAt(note, asOf) && _isDateAtOrBefore(record.date, asOf);
    }
    return _isDateAtOrBefore(record.date, asOf);
  }

  bool _isNoteActiveAt(Note note, DateTime asOf) {
    final from = _parseDate(note.validFrom);
    if (from != null && asOf.isBefore(from)) return false;

    final until = _parseDate(note.validUntil);
    if (until != null && asOf.isAfter(until)) return false;

    return true;
  }

  bool _isDateAtOrBefore(String? date, DateTime asOf) {
    final dt = _parseDate(date);
    if (dt == null) return true;
    return !dt.isAfter(asOf);
  }

  DateTime? _parseDate(String? date) {
    if (date == null || date.isEmpty) return null;
    try {
      return DateTime.parse(date);
    } catch (_) {
      return null;
    }
  }

  String _pad(int value) => value.toString().padLeft(4, '0');

  /// Promotes or expires notes according to [promotionPolicy] and returns the
  /// number of records changed.
  ///
  /// Should be called periodically (e.g. from a background job) rather than
  /// on every write.
  Future<int> maintainMemoryLevels() => _levels.maintain();

  /// Copies a note into another [targetStore] with a provenance marker.
  ///
  /// The copied note receives a `(said in <sourceScope>)` suffix so the
  /// receiving scope can evaluate the source of the fact. Returns the created
  /// record, or null if the note could not be copied (e.g. duplicate).
  Future<MemoryRecord?> copyNoteToScope(
    String noteId,
    KBMemoryStore targetStore, {
    required String sourceScope,
  }) async {
    final record = await findById(noteId);
    if (record == null || record.note == null) return null;

    final note = record.note!;
    final copy = await MemoryProvenanceService.prepareCopy(
      note,
      sourceScope,
      (normalized) async {
        final existing = await targetStore.list(type: 'note', limit: null);
        return existing.any((r) {
          final n = r.note;
          return n != null && normalizeMemoryText(n.text) == normalized;
        });
      },
    );
    if (copy == null) return null;

    return targetStore.addNote(
      text: copy.text,
      author: note.author,
      area: note.area,
      topics: List.of(note.topics),
      tags: List.of(note.tags),
      importance: note.importance,
      memoryType: note.memoryType,
      level: MemoryLevel.raw,
    );
  }
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

  List<String> get tags =>
      question?.tags ?? answer?.tags ?? note?.tags ?? const [];

  String get area => question?.area ?? answer?.area ?? note?.area ?? '';

  String? get memoryType => note?.memoryType;

  String? get validFrom => note?.validFrom;

  String? get validUntil => note?.validUntil;
}
