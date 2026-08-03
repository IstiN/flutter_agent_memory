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

  KBMemoryStore(
    this.storage, {
    this.provider,
    this.source = 'agent',
    this.deduplicateOnCapture = true,
    this.promotionPolicy = const MemoryPromotionPolicy(),
  }) : _parser = KBFileParser(),
       _renderer = const KbMarkdownRenderer();

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

    if (deduplicateOnCapture && await _hasDuplicateQuestionText(question.text)) {
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

    if (deduplicateOnCapture && await _hasDuplicateAnswerText(answer.text)) {
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

    if (deduplicateOnCapture && await _hasDuplicateNote(note)) {
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

    switch (record.entityType) {
      case 'question':
        final q = record.question!;
        final updatedTags = tags ?? q.tags;
        final mergedTags = _renderer.buildEntityTags(
          updatedTags,
          source,
          '#question',
        );
        final updatedText = KBSecretRedactionAgent.redact(text ?? q.text);
        final enriched = await _enrich(
          updatedText,
          area: q.area,
          topics: q.topics,
          tags: mergedTags,
        );
        final updated = q.copyWith(
          text: updatedText,
          tags: enriched.tags,
          topics: enriched.topics,
          area: enriched.area,
          importance: importance ?? q.importance,
        );
        await _writeQuestion(updated);
        return _toRecord(question: updated);
      case 'answer':
        final a = record.answer!;
        final updatedTags = tags ?? a.tags;
        final mergedTags = _renderer.buildEntityTags(
          updatedTags,
          source,
          '#answer',
        );
        final updatedText = KBSecretRedactionAgent.redact(text ?? a.text);
        final enriched = await _enrich(
          updatedText,
          area: a.area,
          topics: a.topics,
          tags: mergedTags,
        );
        final updated = a.copyWith(
          text: updatedText,
          tags: enriched.tags,
          topics: enriched.topics,
          area: enriched.area,
          importance: importance ?? a.importance,
        );
        await _writeAnswer(updated);
        return _toRecord(answer: updated);
      case 'note':
        final n = record.note!;
        final updatedTags = tags ?? n.tags;
        final mergedTags = _renderer.buildEntityTags(
          updatedTags,
          source,
          '#note',
        );
        final updatedText = KBSecretRedactionAgent.redact(text ?? n.text);
        final enriched = await _enrich(
          updatedText,
          area: n.area,
          topics: n.topics,
          tags: mergedTags,
        );
        final updated = n.copyWith(
          text: updatedText,
          tags: enriched.tags,
          topics: enriched.topics,
          area: enriched.area,
          importance: importance ?? n.importance,
          memoryType: memoryType != null
              ? MemoryType.normalize(memoryType)
              : n.memoryType,
          validFrom: validFrom ?? n.validFrom,
          validUntil: validUntil ?? n.validUntil,
          level: level != null ? MemoryLevel.normalize(level) : n.level,
          relations: relations ?? n.relations,
        );
        await _writeNote(updated);
        return _toRecord(note: updated);
      default:
        throw UnsupportedError('Unsupported entity type: ${record.entityType}');
    }
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

  /// Returns true if a note with the same content fingerprint already exists.
  Future<bool> _hasDuplicateNote(Note candidate) async {
    final fingerprint = memoryFingerprint(candidate);
    for (final id in await storage.listEntityIds('note')) {
      final content = await storage.readEntity('note', id);
      if (content == null) continue;
      try {
        final note = _parser.parseNote(content);
        if (memoryFingerprint(note) == fingerprint) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Returns true if a question with the same normalized text already exists.
  Future<bool> _hasDuplicateQuestionText(String text) async {
    final normalized = normalizeMemoryText(text);
    for (final id in await storage.listEntityIds('question')) {
      final content = await storage.readEntity('question', id);
      if (content == null) continue;
      try {
        final q = _parser.parseQuestion(content);
        if (normalizeMemoryText(q.text) == normalized) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Returns true if an answer with the same normalized text already exists.
  Future<bool> _hasDuplicateAnswerText(String text) async {
    final normalized = normalizeMemoryText(text);
    for (final id in await storage.listEntityIds('answer')) {
      final content = await storage.readEntity('answer', id);
      if (content == null) continue;
      try {
        final a = _parser.parseAnswer(content);
        if (normalizeMemoryText(a.text) == normalized) return true;
      } catch (_) {}
    }
    return false;
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
    var resolvedArea = area != null && area.isNotEmpty ? area : 'general';
    var resolvedTopics = topics != null && topics.isNotEmpty
        ? topics
        : <String>[];
    var resolvedTags = tags != null && tags.isNotEmpty ? tags : <String>[];

    if (provider != null &&
        (resolvedArea == 'general' || resolvedTags.isEmpty)) {
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
  Future<MemoryRevision> readMemoryRevision() async {
    final content = (await storage.readFile('MEMORY.md')) ?? '';
    return MemoryRevision(content: content, hash: revisionHash(content));
  }

  /// Writes [content] to [MEMORY.md] only if the current revision matches
  /// [expectedHash]. Returns true when the write succeeded, false if the file
  /// was modified concurrently.
  Future<bool> writeMemoryRevision(
    String content,
    String expectedHash,
  ) async {
    final current = (await storage.readFile('MEMORY.md')) ?? '';
    if (revisionHash(current) != expectedHash) return false;
    await storage.writeFile('MEMORY.md', content);
    return true;
  }

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

    await _writeConsolidation(
      result,
      expectedRevisionHash: expectedRevisionHash,
    );
    return result;
  }

  Future<String?> _readExistingSummary() async {
    return (await storage.readFile('MEMORY.md'))?.trim();
  }

  Future<void> _writeConsolidation(
    ConsolidationResult result, {
    String? expectedRevisionHash,
  }) async {
    final content = result.summary;
    if (expectedRevisionHash != null) {
      final ok = await writeMemoryRevision(content, expectedRevisionHash);
      if (!ok) {
        throw ConcurrentRevisionException(
          'MEMORY.md was modified during consolidation.',
        );
      }
    } else {
      await storage.writeFile('MEMORY.md', content);
    }

    if (result.skills.isEmpty) {
      await _clearSkills();
      return;
    }

    await _clearSkills();
    for (var i = 0; i < result.skills.length; i++) {
      final skill = result.skills[i];
      final id = 'sk_${(i + 1).toString().padLeft(4, '0')}';
      final buffer = StringBuffer()
        ..writeln('---')
        ..writeln('id: $id')
        ..writeln('title: ${skill.title}')
        ..writeln('tags: ${skill.tags.join(', ')}')
        ..writeln('---')
        ..writeln()
        ..writeln(skill.instruction);
      await storage.writeFile('skills/$id.md', buffer.toString());
    }
  }

  Future<void> _clearSkills() async {
    // Best-effort removal: storage backends may not support listing arbitrary
    // files, so we simply overwrite known skill slots with empty content for
    // backends that do. For file storage the old files remain; this is left as
    // a known limitation for non-file backends.
    for (var i = 1; i <= 9999; i++) {
      final id = 'sk_${i.toString().padLeft(4, '0')}';
      final path = 'skills/$id.md';
      if (await storage.readFile(path) == null) break;
      await storage.writeFile(path, '');
    }
  }

  bool _isRecordActiveAt(MemoryRecord record, DateTime asOf) {
    // If the note explicitly declares validity boundaries, use them.
    if (record.note != null) {
      final note = record.note!;
      if (note.validFrom != null && note.validFrom!.isNotEmpty) {
        try {
          final from = DateTime.parse(note.validFrom!);
          if (asOf.isBefore(from)) return false;
        } catch (_) {}
      }
      if (note.validUntil != null && note.validUntil!.isNotEmpty) {
        try {
          final until = DateTime.parse(note.validUntil!);
          if (asOf.isAfter(until)) return false;
        } catch (_) {}
      }
      return true;
    }

    if (record.date.isEmpty) return true;
    try {
      final dt = DateTime.parse(record.date);
      return !dt.isAfter(asOf);
    } catch (_) {
      return true;
    }
  }

  String _pad(int value) => value.toString().padLeft(4, '0');

  /// Promotes or expires notes according to [promotionPolicy] and returns the
  /// number of records changed.
  ///
  /// Should be called periodically (e.g. from a background job) rather than
  /// on every write.
  Future<int> maintainMemoryLevels() async {
    var changed = 0;
    final now = DateTime.parse(currentUtcTimestamp());

    final notes = await list(type: 'note', limit: null);
    for (final record in notes) {
      final note = record.note;
      if (note == null) continue;
      final date = _parseRecordDate(record.date);
      if (date == null) continue;

      final age = now.difference(date);
      if (note.level == MemoryLevel.raw) {
        if (age > promotionPolicy.rawExpiryAfter) {
          await deleteRecord(note.id);
          changed++;
          continue;
        }
        if (age > promotionPolicy.rawToConsolidatedAfter) {
          await _writeNote(note.copyWith(level: MemoryLevel.consolidated));
          changed++;
          continue;
        }
      }
      if (note.level == MemoryLevel.consolidated &&
          age > promotionPolicy.consolidatedToConceptAfter) {
        await _writeNote(note.copyWith(level: MemoryLevel.concept));
        changed++;
      }
    }
    return changed;
  }

  DateTime? _parseRecordDate(String date) {
    if (date.isEmpty) return null;
    try {
      return DateTime.parse(date);
    } catch (_) {
      return null;
    }
  }

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

    final source = sourceScope.replaceAll(RegExp(r'[\r\n()]+'), ' ').trim();
    final provenance = source.isNotEmpty ? source : 'a shared scope';
    final note = record.note!;

    final existing = await targetStore.list(type: 'note', limit: null);
    final normalized = normalizeMemoryText(note.text);
    final alreadyExists = existing.any((r) {
      final n = r.note;
      return n != null && normalizeMemoryText(n.text) == normalized;
    });
    if (alreadyExists) return null;

    final text = note.text.endsWith('.') || note.text.endsWith('!') || note.text.endsWith('?')
        ? '${note.text} (said in $provenance)'
        : '${note.text}. (said in $provenance)';

    return targetStore.addNote(
      text: text,
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

/// Exception thrown when an optimistic concurrency check fails.
class ConcurrentRevisionException implements Exception {
  final String message;
  ConcurrentRevisionException(this.message);

  @override
  String toString() => 'ConcurrentRevisionException: $message';
}

/// A content snapshot plus its SHA-256 revision hash.
class MemoryRevision {
  final String content;
  final String hash;

  const MemoryRevision({required this.content, required this.hash});
}

/// Policy controlling automatic promotion and expiry of memory levels.
///
/// Raw records that survive for [rawToConsolidatedAfter] without contradiction
/// are promoted to consolidated. Consolidated records older than
/// [consolidatedToConceptAfter] are promoted to concept. Raw records that are
/// not confirmed within [rawExpiryAfter] can be removed.
class MemoryPromotionPolicy {
  final Duration rawToConsolidatedAfter;
  final Duration consolidatedToConceptAfter;
  final Duration rawExpiryAfter;

  const MemoryPromotionPolicy({
    this.rawToConsolidatedAfter = const Duration(days: 14),
    this.consolidatedToConceptAfter = const Duration(days: 90),
    this.rawExpiryAfter = const Duration(days: 30),
  });
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
