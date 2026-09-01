import 'dart:async';

import '../models/kb_context.dart';

/// Abstract storage backend for the agent knowledge base.
///
/// Implementations can target the local file system, in-memory maps,
/// browser storage, SQLite, or custom HTTP endpoints. The rest of the
/// framework works with Markdown content strings, so any backend that can
/// store and retrieve UTF-8 text can be plugged in.
///
/// Most methods return [FutureOr] so that synchronous backends (file,
/// in-memory, SQLite) and asynchronous backends (HTTP, cloud) can implement
/// the same interface. Callers should `await` all storage operations.
abstract interface class KbStorage {
  /// Initializes the backend (creates directories, tables, buckets, etc.).
  FutureOr<void> initialize({bool clean = false});

  /// Loads existing context: next IDs, people, topics, question summaries.
  FutureOr<KBContext> loadContext();

  /// Reads the raw Markdown content of an entity.
  ///
  /// [type] is one of `question`, `answer`, `note`.
  /// Returns `null` if the entity does not exist.
  FutureOr<String?> readEntity(String type, String id);

  /// Writes raw Markdown content for an entity.
  ///
  /// [type] is one of `question`, `answer`, `note`.
  FutureOr<void> writeEntity(String type, String id, String content);

  /// Deletes an entity.
  FutureOr<void> deleteEntity(String type, String id);

  /// Lists all entity ids of the given [type].
  FutureOr<List<String>> listEntityIds(String type);

  /// Reads a structure/index/graph file by its logical path.
  ///
  /// Examples: `INDEX.md`, `GRAPH.md`, `stats/activity_timeline.md`,
  /// `topics/state-management.md`.
  /// Returns `null` if the file does not exist.
  FutureOr<String?> readFile(String path);

  /// Writes a structure/index/graph file.
  FutureOr<void> writeFile(String path, String content);

  /// Lists logical paths of stored files that start with [prefix].
  ///
  /// Examples:
  /// - `prefix = 'topics'` -> `['topics/dart.md', 'topics/state-management.md']`
  /// - `prefix = 'people'` -> `['people/alice/alice.md']`
  FutureOr<List<String>> listFilePaths(String prefix);

  /// Returns a human-readable location for an entity.
  ///
  /// For file storage this is the absolute file path. For other backends it
  /// can be a URI, key, or table primary key.
  String describeLocation(String type, String id);
}

/// Optional capability for storages that can append to a file natively.
///
/// Implementing this makes append-only files (the `DELETIONS.md` tombstone
/// ledger) safe against concurrent writers: on a filesystem backend an
/// append is a single operation, so two racing deletes both land instead of
/// the classic read-modify-write last-writer-wins data loss.
abstract interface class KbAppendCapable {
  /// Appends [content] to the file at [path], creating it if needed.
  FutureOr<void> appendFile(String path, String content);
}

/// Uniform append access for any [KbStorage].
///
/// Storages implementing [KbAppendCapable] get their native append;
/// everything else falls back to read-modify-write (documented best-effort
/// under concurrent writes).
extension KbStorageAppend on KbStorage {
  /// Appends [content] to the file at [path].
  Future<void> appendToFile(String path, String content) async {
    final storage = this;
    if (storage is KbAppendCapable) {
      await (storage as KbAppendCapable).appendFile(path, content);
      return;
    }
    final existing = await readFile(path) ?? '';
    await writeFile(path, '$existing$content');
  }
}
