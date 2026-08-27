import 'dart:async';

import '../../utils/memory_utils.dart';
import '../kb_storage.dart';

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

/// Manages optimistic concurrency for the top-level MEMORY.md summary file.
///
/// The revision hash mixes in a generation counter stored in
/// [generationFile]. Deletion of memory records bumps the generation, so a
/// consolidation that started before the delete fails its conditional write
/// instead of writing a summary that resurrects the deleted record.
class MemoryRevisionService {
  final KbStorage storage;
  static const String _memoryFile = 'MEMORY.md';
  static const String generationFile = 'MEMORY.revision';

  MemoryRevisionService(this.storage);

  /// Reads the current [MEMORY.md] file and returns its revision hash along
  /// with the content.
  Future<MemoryRevision> read() async {
    final content = (await storage.readFile(_memoryFile)) ?? '';
    final generation = await _readGeneration();
    return MemoryRevision(content: content, hash: _hash(content, generation));
  }

  /// Writes [content] to [MEMORY.md] only if the current revision matches
  /// [expectedHash]. Returns true when the write succeeded, false if the file
  /// was modified concurrently (or a record was deleted in the meantime).
  Future<bool> write(String content, String expectedHash) async {
    final current = (await storage.readFile(_memoryFile)) ?? '';
    final generation = await _readGeneration();
    if (_hash(current, generation) != expectedHash) return false;
    await storage.writeFile(_memoryFile, content);
    return true;
  }

  /// Increments the revision generation, invalidating any expected hash that
  /// was read before this call.
  Future<void> bump() async {
    final generation = await _readGeneration();
    await storage.writeFile(generationFile, '${generation + 1}');
  }

  Future<int> _readGeneration() async {
    final raw = await storage.readFile(generationFile);
    if (raw == null) return 0;
    return int.tryParse(raw.trim()) ?? 0;
  }

  String _hash(String content, int generation) {
    // Generation 0 (no counter file) keeps the legacy hash so expectations
    // read before any deletion remain compatible.
    if (generation == 0) return revisionHash(content);
    return revisionHash('$generation\u0000$content');
  }
}
