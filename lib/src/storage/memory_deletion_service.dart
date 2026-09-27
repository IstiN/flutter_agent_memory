import 'dart:async';

import '../utils/date_utils.dart';
import '../utils/memory_utils.dart';
import 'kb_file_parser.dart';
import 'kb_graph_builder.dart';
import 'kb_storage.dart';
import 'memory/memory_revision_service.dart';

/// A single tombstone entry from the deletion ledger (`DELETIONS.md`).
class MemoryDeletion {
  /// Monotonic sequence number of the deletion (1-based).
  final int seq;

  /// Deleted record id (`q_0001`, `a_0002`, `n_0003`, ...).
  final String id;

  /// Entity type: `question`, `answer` or `note`.
  final String type;

  /// SHA-256 fingerprint of the normalized record text.
  final String fingerprint;

  /// UTC timestamp of the deletion.
  final String deletedAt;

  /// Trimmed single-line excerpt of the deleted text (for consolidation
  /// cleanup notices).
  final String text;

  const MemoryDeletion({
    required this.seq,
    required this.id,
    required this.type,
    required this.fingerprint,
    required this.deletedAt,
    required this.text,
  });
}

/// Outcome of a delete operation.
///
/// [deletedIds] lists the record ids that were actually removed; it is empty
/// when nothing matched (delete operations are idempotent).
class MemoryDeleteResult {
  final List<String> deletedIds;

  const MemoryDeleteResult(this.deletedIds);

  /// True when at least one record was removed.
  bool get deleted => deletedIds.isNotEmpty;

  @override
  String toString() => 'MemoryDeleteResult(${deletedIds.join(', ')})';
}

/// Safe deletion of memory records shared by several agent processes.
///
/// Deleting a record through this service does three things:
///
/// 1. Removes the entity — on git-backed storages implementing
///    [KbTombstoneCapable] (the file backend does) the file is rewritten
///    in place as a tombstone instead of being unlinked, so a delete can
///    never produce a git delete/modify conflict: both sides of a merge
///    only ever modify files. Other backends fall back to a physical
///    delete. In both cases [KbStorage.readEntity] reports the entity as
///    absent afterwards.
/// 2. Appends a tombstone entry to `DELETIONS.md` so capture-time
///    deduplication can keep deleted garbage from being re-added by another
///    process working from the same transcript.
/// 3. Bumps the MEMORY.md revision generation, so a consolidation running
///    concurrently in another process fails its conditional write instead of
///    resurrecting the deleted record in the summary.
///
/// The ledger is strictly append-only: deletions and consolidation-cursor
/// updates add lines without rewriting existing content, so a delete can
/// never clobber tombstones written by another process, merged from another
/// git branch, or recorded by an older/foreign format version. On storages
/// implementing [KbAppendCapable] (the file backend does) appends are
/// atomic enough for concurrent writers to both land; other backends fall
/// back to best-effort read-modify-write. The ledger is compacted
/// (rewritten, deduplicated) only after it grows past twice
/// [maxLedgerEntries], and compaction refuses to touch content it cannot
/// parse.
///
/// Tombstone files accumulate until [purgeTombstones] runs during a
/// maintenance window; the `deleted/` record files (and the legacy ledger)
/// keep the history, so purging never loses the fact that a record was
/// deleted.
///
/// The authoritative, conflict-free deletion record lives in the
/// [deletedDir] directory: one small deterministic file per deleted record
/// (`<id>_<fingerprint8>.md`). Recording a deletion is only ever a file
/// creation — two branches deleting the same record produce the identical
/// file, and different deletions are independent files — so concurrent
/// agents in different git branches can never conflict, and consolidation
/// progress is a local set difference against [processedMarkerFile] rather
/// than a shared cursor.
class MemoryDeletionService {
  final KbStorage storage;
  final KBFileParser parser;
  final MemoryRevisionService revision;
  final int maxLedgerEntries;

  static const String ledgerFile = 'DELETIONS.md';

  /// Per-record deletion directory: one small file per deleted record,
  /// named `<id>_<fingerprint8>.md` with deterministic content.
  ///
  /// This is the conflict-free deletion record: adding a deletion is only
  /// ever a file *creation* (two branches deleting the same record produce
  /// the identical file — same name, same bytes — which git merges
  /// trivially; different deletions are different files and never interact).
  /// There is no shared mutable file, no global counter, and no cursor that
  /// could lose entries across branches.
  static const String deletedDir = 'deleted';

  /// Local, gitignored marker listing the fingerprints whose deletions the
  /// local consolidation has already been warned about (set difference for
  /// [unprocessedDeletions]). A derivative like `.last_maintenance`.
  static const String processedMarkerFile = '.last_deletions';

  MemoryDeletionService(
    this.storage, {
    KBFileParser? parser,
    MemoryRevisionService? revision,
    this.maxLedgerEntries = 500,
  }) : parser = parser ?? KBFileParser(),
       revision = revision ?? MemoryRevisionService(storage);

  /// Deletes a record by id. Returns the ids that were removed.
  Future<MemoryDeleteResult> deleteById(
    String id, {
    bool rebuildGraph = false,
  }) async {
    final type = typeFromId(id);
    if (type == null) return const MemoryDeleteResult([]);
    final content = await storage.readEntity(type, id);
    if (content == null) return const MemoryDeleteResult([]);

    final text = _extractText(type, content);
    await _removeEntity(type, id);
    await _recordDeletion(id, type, text);
    await _maybeRebuildGraph(rebuildGraph);
    return MemoryDeleteResult([id]);
  }

  /// Deletes every record whose normalized text matches [text] exactly.
  ///
  /// [type] optionally restricts the scan to `question`, `answer` or `note`.
  Future<MemoryDeleteResult> deleteByText(
    String text, {
    String? type,
    bool rebuildGraph = false,
  }) async {
    final normalized = normalizeMemoryText(text);
    if (normalized.isEmpty) return const MemoryDeleteResult([]);

    final types = type != null ? [type.toLowerCase()] : _allTypes;
    final deleted = <String>[];
    for (final t in types) {
      deleted.addAll(await _deleteMatchingInType(normalized, t));
    }

    if (deleted.isNotEmpty) await _maybeRebuildGraph(rebuildGraph);
    return MemoryDeleteResult(deleted);
  }

  Future<List<String>> _deleteMatchingInType(
    String normalized,
    String type,
  ) async {
    final deleted = <String>[];
    for (final id in await storage.listEntityIds(type)) {
      final removedId = await _deleteIfTextMatches(normalized, type, id);
      if (removedId != null) deleted.add(removedId);
    }
    return deleted;
  }

  Future<String?> _deleteIfTextMatches(
    String normalized,
    String type,
    String id,
  ) async {
    final content = await storage.readEntity(type, id);
    if (content == null) return null;
    final entityText = _extractText(type, content);
    if (entityText == null) return null;
    if (normalizeMemoryText(entityText) != normalized) return null;
    await _removeEntity(type, id);
    await _recordDeletion(id, type, entityText);
    return id;
  }

  /// True when [id] is present among the deleted records.
  ///
  /// Checks the per-record `deleted/` directory first (current mechanism),
  /// then the legacy `DELETIONS.md` ledger (records deleted before the
  /// `deleted/` mechanism existed, or on storages without tombstone files).
  Future<bool> isDeleted(String id) async {
    final prefix = '${id}_';
    for (final path in await storage.listFilePaths(deletedDir)) {
      if (_baseName(path).startsWith(prefix)) return true;
    }
    final ledger = _parseLedger(await storage.readFile(ledgerFile));
    return ledger.any((d) => d.id == id);
  }

  /// True when text with the same normalized fingerprint was deleted.
  Future<bool> hasDeletedText(String text) async {
    final fingerprint = memoryTextFingerprint(text);
    if (await _deletedFileForFingerprint(fingerprint) != null) return true;
    final ledger = _parseLedger(await storage.readFile(ledgerFile));
    return ledger.any((d) => d.fingerprint == fingerprint);
  }

  /// Deletions a consolidation run has not been warned about yet — the
  /// per-record files in `deleted/` whose fingerprint is not in the local,
  /// gitignored [processedMarkerFile] marker.
  ///
  /// Unlike the legacy [pendingDeletions] cursor (a shared global `seq`
  /// counter), this is a set difference: it survives branching and merging
  /// — deletions that arrive from another branch after the marker was
  /// written are still reported, so cleanup notices can never be lost.
  Future<List<MemoryDeletion>> unprocessedDeletions({int limit = 50}) async {
    final processed = _parseMarker(await storage.readFile(processedMarkerFile));
    final pending = <MemoryDeletion>[];
    for (final path in await storage.listFilePaths(deletedDir)) {
      final deletion = _parseDeletedFile(
        _baseName(path),
        await storage.readFile(path) ?? '',
      );
      if (deletion == null || processed.contains(deletion.fingerprint)) {
        continue;
      }
      pending.add(deletion);
    }
    pending.sort((a, b) => a.id.compareTo(b.id));
    if (pending.length > limit) pending.removeRange(0, pending.length - limit);
    return pending;
  }

  /// Marks [deletions] as processed: adds their fingerprints to the local
  /// [processedMarkerFile] marker, so [unprocessedDeletions] stops
  /// reporting them.
  ///
  /// The marker is a derivative file (kept out of git by
  /// [MemoryRepoInit]), so it is never involved in merges — each clone
  /// tracks its own consolidation progress independently.
  Future<void> markDeletionsProcessed(List<MemoryDeletion> deletions) async {
    if (deletions.isEmpty) return;
    final processed = _parseMarker(await storage.readFile(processedMarkerFile));
    processed.addAll(deletions.map((d) => d.fingerprint));
    final lines = processed.toList()..sort();
    await storage.writeFile(processedMarkerFile, '${lines.join('\n')}\n');
  }

  /// Ledger entries with [seq] greater than the consolidation cursor — the
  /// deletions a consolidation run has not yet been warned about.
  ///
  /// Legacy API kept for backward compatibility; new code should use
  /// [unprocessedDeletions], which cannot lose deletions across git
  /// branches (the `seq` cursor is a global counter that does not survive
  /// branching: deletions merged in after the cursor was written are never
  /// reported again).
  Future<List<MemoryDeletion>> pendingDeletions({int limit = 50}) async {
    final (ledger, cursor) = _parseLedgerWithCursor(
      await storage.readFile(ledgerFile),
    );
    final pending = ledger.where((d) => d.seq > cursor).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    if (pending.length > limit) pending.removeRange(0, pending.length - limit);
    return pending;
  }

  /// Advances the consolidation cursor so processed deletions are not fed to
  /// the consolidation agent again.
  ///
  /// Append-only: writes a new `consolidatedUpTo:` line instead of
  /// rewriting the file — the parser takes the max over all cursor lines,
  /// and git merges cursor lines by union.
  Future<void> markConsolidated(int seq) async {
    final existing = await storage.readFile(ledgerFile);
    final (_, cursor) = _parseLedgerWithCursor(existing);
    if (seq <= cursor) return;
    if (existing == null) {
      await storage.writeFile(ledgerFile, _ledgerHeader(seq));
      return;
    }
    await storage.appendToFile(ledgerFile, 'consolidatedUpTo: $seq\n');
  }

  /// Renders cleanup instructions for [deletions] so the consolidation agent
  /// removes statements sourced from deleted records instead of merging them
  /// forward into MEMORY.md. Returns [extraInstructions] unchanged when the
  /// list is empty.
  static String buildCleanupNotices(
    String extraInstructions,
    List<MemoryDeletion> deletions,
  ) {
    if (deletions.isEmpty) return extraInstructions;
    final notices = deletions
        .map((d) => '- ${d.type} ${d.id}: ${d.text.isEmpty ? d.id : d.text}')
        .join('\n');
    final prefix = extraInstructions.isEmpty ? '' : '$extraInstructions\n';
    return '$prefix'
        'The following memory records were deleted by the user since the last '
        'consolidation. Remove any statements derived from them from the '
        'summary instead of preserving them:\n$notices';
  }

  // --- internals -----------------------------------------------------------

  /// Removes the entity: tombstone-in-place on git-backed file storage so
  /// merges never see a file deletion, physical delete everywhere else.
  Future<void> _removeEntity(String type, String id) async {
    final s = storage;
    if (s is KbTombstoneCapable) {
      await (s as KbTombstoneCapable).tombstoneEntity(type, id);
    } else {
      await s.deleteEntity(type, id);
    }
  }

  /// Physically removes tombstoned entity files (git-backed file storage
  /// only; other backends delete eagerly and have nothing to purge).
  ///
  /// Run during maintenance when no concurrent agent is writing memory —
  /// purging re-introduces file deletions into git history, which is safe
  /// only when nothing else touches the same files. The deletion ledger
  /// (`DELETIONS.md`) is the durable record of what was deleted, so purge
  /// loses no history.
  Future<List<String>> purgeTombstones() async {
    final s = storage;
    if (s is KbTombstoneCapable) {
      return await (s as KbTombstoneCapable).purgeTombstones();
    }
    return const [];
  }

  static const List<String> _allTypes = ['question', 'answer', 'note'];

  String? _extractText(String type, String content) {
    try {
      switch (type) {
        case 'question':
          return parser.parseQuestion(content).text;
        case 'answer':
          return parser.parseAnswer(content).text;
        case 'note':
          return parser.parseNote(content).text;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _recordDeletion(String id, String type, String? text) async {
    final existing = await storage.readFile(ledgerFile);
    final (entries, _) = _parseLedgerWithCursor(existing);
    final maxSeq = entries.isEmpty
        ? 0
        : entries.map((e) => e.seq).reduce((a, b) => a > b ? a : b);
    final entry = MemoryDeletion(
      seq: maxSeq + 1,
      id: id,
      type: type,
      fingerprint: memoryTextFingerprint(text ?? id),
      deletedAt: currentUtcTimestamp(),
      text: _sanitizeLedgerText(text ?? ''),
    );
    if (existing == null) {
      await storage.writeFile(ledgerFile, _ledgerHeader(0));
    }
    // Append-only: the previous ledger content is never rewritten, so a
    // delete can never destroy tombstones written by another process,
    // another branch, or an older/foreign format version.
    await storage.appendToFile(ledgerFile, _formatEntry(entry));
    // The per-record deletion file is the durable, conflict-free record
    // used by isDeleted/hasDeletedText/unprocessedDeletions. Content is
    // deterministic (no wall clock, no volatile fields) so concurrent
    // branches produce byte-identical files for the same deletion.
    await storage.writeFile(
      _deletedFileName(entry.id, entry.fingerprint),
      _formatDeletedFile(entry),
    );
    await revision.bump();
    await _maybeCompact(entries);
  }

  /// Rewrites the ledger only when it grew past twice [maxLedgerEntries] —
  /// the single rare read-modify-write path. Refuses to run on a ledger it
  /// could not parse at all, so unrecognized content is never clobbered.
  Future<void> _maybeCompact(List<MemoryDeletion> entries) async {
    if (entries.isEmpty || entries.length < maxLedgerEntries * 2) return;
    final (_, cursor) = _parseLedgerWithCursor(
      await storage.readFile(ledgerFile),
    );
    final kept = entries.sublist(entries.length - maxLedgerEntries);
    await _writeLedger(kept, consolidatedUpTo: cursor);
  }

  static String _ledgerHeader(int consolidatedUpTo) =>
      '---\nconsolidatedUpTo: $consolidatedUpTo\n---\n';

  static String _formatEntry(MemoryDeletion e) =>
      '- seq: ${e.seq} | id: ${e.id} | type: ${e.type} | '
      'fingerprint: ${e.fingerprint} | deletedAt: ${e.deletedAt} | '
      'text: ${e.text}\n';

  // --- per-record deleted/ files -------------------------------------------

  static String _deletedFileName(String id, String fingerprint) =>
      '$deletedDir/${id}_${fingerprint.substring(0, 8)}.md';

  /// Deterministic content: identical for the same (id, fingerprint, text)
  /// on every branch and every machine, so git add/add merges of the same
  /// deletion are trivial. `deletedAt` lives in the legacy ledger and the
  /// tombstone entity file, not here.
  static String _formatDeletedFile(MemoryDeletion e) =>
      '''
---
id: ${e.id}
fingerprint: ${e.fingerprint}
type: ${e.type}
---

${e.text}
''';

  static MemoryDeletion? _parseDeletedFile(String baseName, String content) {
    String? field(String key) {
      final match = RegExp(
        '^$key:[ \\t]*(.*)\$',
        multiLine: true,
      ).firstMatch(content);
      return match?.group(1)?.trim();
    }

    final id = field('id') ?? '';
    if (id.isEmpty) return null;
    var fingerprint = field('fingerprint') ?? '';
    var type = field('type') ?? '';
    if (type.isEmpty) type = typeFromId(id) ?? '';
    if (fingerprint.isEmpty) fingerprint = memoryTextFingerprint(id);
    // Body after the frontmatter block is the text excerpt.
    final body = content.split('\n---\n').last.trim();
    return MemoryDeletion(
      seq: 0,
      id: id,
      type: type,
      fingerprint: fingerprint,
      deletedAt: '',
      text: body,
    );
  }

  /// The `deleted/` file for [fingerprint] when it exists.
  Future<MemoryDeletion?> _deletedFileForFingerprint(String fingerprint) async {
    final suffix = '_${fingerprint.substring(0, 8)}.md';
    for (final path in await storage.listFilePaths(deletedDir)) {
      if (_baseName(path).endsWith(suffix)) {
        return _parseDeletedFile(
          _baseName(path),
          await storage.readFile(path) ?? '',
        );
      }
    }
    return null;
  }

  static String _baseName(String path) =>
      path.replaceAll('\\', '/').split('/').last;

  // --- processed marker -----------------------------------------------------

  static Set<String> _parseMarker(String? content) => content == null
      ? <String>{}
      : content
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toSet();

  String _sanitizeLedgerText(String text) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final withoutPipes = oneLine.replaceAll('|', '/');
    return withoutPipes.length > 160
        ? '${withoutPipes.substring(0, 157)}...'
        : withoutPipes;
  }

  Future<void> _maybeRebuildGraph(bool rebuildGraph) async {
    if (!rebuildGraph) return;
    try {
      await KBGraphBuilder(storage).build();
    } catch (_) {
      // Graph rebuild is a consistency nicety; never fail the delete for it.
    }
  }

  Future<void> _writeLedger(
    List<MemoryDeletion> entries, {
    required int consolidatedUpTo,
  }) async {
    final buffer = StringBuffer(_ledgerHeader(consolidatedUpTo));
    for (final e in entries) {
      buffer.write(_formatEntry(e));
    }
    await storage.writeFile(ledgerFile, buffer.toString());
  }

  List<MemoryDeletion> _parseLedger(String? content) =>
      _parseLedgerWithCursor(content).$1;

  /// Parses the append-only line ledger, tolerating git union-merge output:
  /// duplicate entry lines are collapsed by (seq, id), entries are sorted by
  /// seq, and the consolidation cursor is the max over every
  /// `consolidatedUpTo:` line (a union merge may contain several headers).
  (List<MemoryDeletion>, int) _parseLedgerWithCursor(String? content) {
    if (content == null || content.isEmpty) return (const [], 0);
    var cursor = 0;
    final entries = <MemoryDeletion>[];
    final seen = <String>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      final cursorValue = _parseCursorLine(trimmed);
      if (cursorValue != null) {
        if (cursorValue > cursor) cursor = cursorValue;
        continue;
      }
      final entry = _parseEntryLine(trimmed);
      if (entry != null && seen.add('${entry.seq}|${entry.id}')) {
        entries.add(entry);
      }
    }
    entries.sort((a, b) => a.seq.compareTo(b.seq));
    return (entries, cursor);
  }

  int? _parseCursorLine(String line) {
    if (!line.startsWith('consolidatedUpTo:')) return null;
    return int.tryParse(line.split(':')[1].trim()) ?? 0;
  }

  MemoryDeletion? _parseEntryLine(String line) =>
      line.startsWith('- seq:') ? _parseEntry(line) : null;

  MemoryDeletion? _parseEntry(String line) {
    final fields = _parseLedgerFields(line);
    final seq = int.tryParse(fields['seq'] ?? '');
    final id = fields['id'] ?? '';
    // Tolerate entries written by older/foreign formats: the type can be
    // derived from the id prefix, the fingerprint recomputed from the text.
    var type = fields['type'] ?? '';
    if (type.isEmpty && id.isNotEmpty) type = typeFromId(id) ?? '';
    final text = fields['text'] ?? '';
    var fingerprint = fields['fingerprint'] ?? '';
    if (fingerprint.isEmpty && text.isNotEmpty) {
      fingerprint = memoryTextFingerprint(text);
    }
    if (seq == null || id.isEmpty || type.isEmpty) return null;
    return MemoryDeletion(
      seq: seq,
      id: id,
      type: type,
      fingerprint: fingerprint,
      deletedAt: fields['deletedAt'] ?? '',
      text: text,
    );
  }

  /// Splits a `- key: value | key: value | ...` line into a field map.
  Map<String, String> _parseLedgerFields(String line) {
    final fields = <String, String>{};
    for (final part in line.substring(2).split('|')) {
      final idx = part.indexOf(':');
      if (idx <= 0) continue;
      fields[part.substring(0, idx).trim()] = part.substring(idx + 1).trim();
    }
    return fields;
  }
}

/// Maps a record id prefix to its entity type (`q_` → question, ...).
String? typeFromId(String id) {
  final lower = id.toLowerCase();
  if (lower.startsWith('q_')) return 'question';
  if (lower.startsWith('a_')) return 'answer';
  if (lower.startsWith('n_')) return 'note';
  return null;
}
