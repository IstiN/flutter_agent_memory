import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/memory_level.dart';
import '../models/note.dart';

/// Normalizes a memory text for duplicate detection.
///
/// Collapses whitespace, strips leading bullets and dates, lower-cases, and
/// removes trailing provenance markers like `(said in ...)`.
String normalizeMemoryText(String text) {
  var cleaned = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[\-*•]\s*'), '')
      .replaceAll(RegExp(r'^\(\d{4}-\d{2}-\d{2}\)\s*'), '')
      .replaceAll(
        RegExp(r'\s+\(said in [^)]+\)\s*$', caseSensitive: false),
        '',
      );
  return cleaned.toLowerCase();
}

/// Computes a SHA-256 hash of [content] and returns it as a hex string.
String revisionHash(String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return sha256.convert(bytes).toString();
}

/// Computes a stable fingerprint of a record text for tombstone bookkeeping.
///
/// Normalizes the text first, so a deleted record blocks re-capture of the
/// same content regardless of whitespace, casing, or bullet prefixes.
String memoryTextFingerprint(String text) =>
    revisionHash(normalizeMemoryText(text));

/// Builds a stable fingerprint for a note based on content and level.
///
/// Used for capture-time deduplication. Two notes with the same normalized
/// text at the same level are considered duplicates even if their IDs differ.
String memoryFingerprint(Note note) =>
    '${MemoryLevel.nameOf(note.level)}:${normalizeMemoryText(note.text)}';
