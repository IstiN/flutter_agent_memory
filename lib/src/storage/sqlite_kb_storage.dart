import 'dart:async';

import 'package:sqlite3/sqlite3.dart';

import 'kb_storage.dart';
import 'kb_storage_context_mixin.dart';

/// SQLite implementation of [KbStorage].
///
/// Stores Markdown entities and structure files in a local SQLite database.
/// Useful for mobile/desktop Flutter apps or any environment where a single
/// file database is preferable to a directory tree.
///
/// The caller provides an opened [Database] instance (from `package:sqlite3`).
class SqliteKbStorage with KbStorageContextMixin implements KbStorage {
  final Database _db;

  SqliteKbStorage(this._db) {
    _ensureSchema();
  }

  void _ensureSchema() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS entities (
        type TEXT NOT NULL,
        id TEXT NOT NULL,
        content TEXT NOT NULL,
        PRIMARY KEY (type, id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS files (
        path TEXT PRIMARY KEY NOT NULL,
        content TEXT NOT NULL
      );
    ''');
  }

  @override
  FutureOr<void> initialize({bool clean = false}) {
    if (clean) {
      _db.execute('DELETE FROM entities;');
      _db.execute('DELETE FROM files;');
    }
    _ensureSchema();
  }

  @override
  String? readEntity(String type, String id) {
    final result = _db.select(
      'SELECT content FROM entities WHERE type = ? AND id = ?;',
      [type, id],
    );
    if (result.isEmpty) return null;
    return result.first['content'] as String;
  }

  @override
  void writeEntity(String type, String id, String content) {
    _db.execute(
      'INSERT OR REPLACE INTO entities (type, id, content) VALUES (?, ?, ?);',
      [type, id, content],
    );
  }

  @override
  void deleteEntity(String type, String id) {
    _db.execute('DELETE FROM entities WHERE type = ? AND id = ?;', [type, id]);
  }

  @override
  List<String> listEntityIds(String type) {
    final result = _db.select(
      'SELECT id FROM entities WHERE type = ? ORDER BY id;',
      [type],
    );
    return result.map((row) => row['id'] as String).toList();
  }

  @override
  String? readFile(String path) {
    final result = _db.select('SELECT content FROM files WHERE path = ?;', [
      path,
    ]);
    if (result.isEmpty) return null;
    return result.first['content'] as String;
  }

  @override
  void writeFile(String path, String content) {
    _db.execute('INSERT OR REPLACE INTO files (path, content) VALUES (?, ?);', [
      path,
      content,
    ]);
  }

  @override
  List<String> listFilePaths(String prefix) {
    final result = _db.select(
      'SELECT path FROM files WHERE path LIKE ? ORDER BY path;',
      ['$prefix%'],
    );
    return result.map((row) => row['path'] as String).toList();
  }

  @override
  String describeLocation(String type, String id) => 'sqlite://$type/$id';
}
