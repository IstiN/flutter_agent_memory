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
class MemoryRevisionService {
  final KbStorage storage;
  static const String _memoryFile = 'MEMORY.md';

  MemoryRevisionService(this.storage);

  /// Reads the current [MEMORY.md] file and returns its revision hash along
  /// with the content.
  Future<MemoryRevision> read() async {
    final content = (await storage.readFile(_memoryFile)) ?? '';
    return MemoryRevision(content: content, hash: revisionHash(content));
  }

  /// Writes [content] to [MEMORY.md] only if the current revision matches
  /// [expectedHash]. Returns true when the write succeeded, false if the file
  /// was modified concurrently.
  Future<bool> write(String content, String expectedHash) async {
    final current = (await storage.readFile(_memoryFile)) ?? '';
    if (revisionHash(current) != expectedHash) return false;
    await storage.writeFile(_memoryFile, content);
    return true;
  }
}
