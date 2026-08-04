import 'dart:async';

import '../../models/note.dart';
import '../../utils/memory_utils.dart';
import '../kb_file_parser.dart';
import '../kb_storage.dart';

/// Encapsulates capture-time duplicate detection for questions, answers and
/// notes.
class MemoryDedupService {
  final KbStorage storage;
  final KBFileParser parser;

  MemoryDedupService(this.storage, this.parser);

  /// Returns true if a question with the same normalized text already exists.
  Future<bool> hasDuplicateQuestion(String text) async {
    final normalized = normalizeMemoryText(text);
    for (final id in await storage.listEntityIds('question')) {
      final content = await storage.readEntity('question', id);
      if (content == null) continue;
      try {
        final q = parser.parseQuestion(content);
        if (normalizeMemoryText(q.text) == normalized) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Returns true if an answer with the same normalized text already exists.
  Future<bool> hasDuplicateAnswer(String text) async {
    final normalized = normalizeMemoryText(text);
    for (final id in await storage.listEntityIds('answer')) {
      final content = await storage.readEntity('answer', id);
      if (content == null) continue;
      try {
        final a = parser.parseAnswer(content);
        if (normalizeMemoryText(a.text) == normalized) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Returns true if a note with the same content fingerprint already exists.
  Future<bool> hasDuplicateNote(Note candidate) async {
    final fingerprint = memoryFingerprint(candidate);
    for (final id in await storage.listEntityIds('note')) {
      final content = await storage.readEntity('note', id);
      if (content == null) continue;
      try {
        final note = parser.parseNote(content);
        if (memoryFingerprint(note) == fingerprint) return true;
      } catch (_) {}
    }
    return false;
  }
}
