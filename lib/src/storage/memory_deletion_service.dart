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
/// 1. Removes the entity file atomically (unlink for file storage,
///    transactional `DELETE` for SQLite, ...).
/// 2. Appends a tombstone entry to `DELETIONS.md` so capture-time
///    deduplication can keep deleted garbage from being re-added by another
///    process working from the same transcript.
/// 3. Bumps the MEMORY.md revision generation, so a consolidation running
///    concurrently in another process fails its conditional write instead of
///    resurrecting the deleted record in the summary.
///
/// The ledger write itself is a read-modify-write of a single file and is
/// therefore best-effort under concurrent writers: the entity deletion is
/// always atomic, but two simultaneous deletes may lose one tombstone entry.
/// Entries are capped at [maxLedgerEntries] (oldest dropped) to keep the
/// ledger file bounded.
class MemoryDeletionService {
  final KbStorage storage;
  final KBFileParser parser;
  final MemoryRevisionService revision;
  final int maxLedgerEntries;

  static const String ledgerFile = 'DELETIONS.md';

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
    await storage.deleteEntity(type, id);
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
    await storage.deleteEntity(type, id);
    await _recordDeletion(id, type, entityText);
    return id;
  }

  /// True when [id] is present in the deletion ledger.
  Future<bool> isDeleted(String id) async {
    final ledger = _parseLedger(await storage.readFile(ledgerFile));
    return ledger.any((d) => d.id == id);
  }

  /// True when text with the same normalized fingerprint was deleted.
  Future<bool> hasDeletedText(String text) async {
    final fingerprint = memoryTextFingerprint(text);
    final ledger = _parseLedger(await storage.readFile(ledgerFile));
    return ledger.any((d) => d.fingerprint == fingerprint);
  }

  /// Ledger entries with [seq] greater than the consolidation cursor — the
  /// deletions a consolidation run has not yet been warned about.
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
  Future<void> markConsolidated(int seq) async {
    final (_, cursor) = _parseLedgerWithCursor(
      await storage.readFile(ledgerFile),
    );
    if (seq <= cursor) return;
    final (entries, _) = _parseLedgerWithCursor(
      await storage.readFile(ledgerFile),
    );
    await _writeLedger(entries, consolidatedUpTo: seq);
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
    final (entries, cursor) = _parseLedgerWithCursor(
      await storage.readFile(ledgerFile),
    );
    final nextSeq = (entries.isEmpty ? 0 : entries.last.seq) + 1;
    final entry = MemoryDeletion(
      seq: nextSeq,
      id: id,
      type: type,
      fingerprint: memoryTextFingerprint(text ?? id),
      deletedAt: currentUtcTimestamp(),
      text: _sanitizeLedgerText(text ?? ''),
    );
    final trimmed = entries.length >= maxLedgerEntries
        ? entries.sublist(entries.length - maxLedgerEntries + 1)
        : entries;
    await _writeLedger([...trimmed, entry], consolidatedUpTo: cursor);
    await revision.bump();
  }

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
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('consolidatedUpTo: $consolidatedUpTo')
      ..writeln('---');
    for (final e in entries) {
      buffer.writeln(
        '- seq: ${e.seq} | id: ${e.id} | type: ${e.type} | '
        'fingerprint: ${e.fingerprint} | deletedAt: ${e.deletedAt} | '
        'text: ${e.text}',
      );
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
    final type = fields['type'] ?? '';
    if (seq == null || id.isEmpty || type.isEmpty) return null;
    return MemoryDeletion(
      seq: seq,
      id: id,
      type: type,
      fingerprint: fields['fingerprint'] ?? '',
      deletedAt: fields['deletedAt'] ?? '',
      text: fields['text'] ?? '',
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
