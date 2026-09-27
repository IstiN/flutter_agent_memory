import 'dart:async';
import 'dart:io';

import '../models/kb_context.dart';
import '../utils/date_utils.dart';
import 'kb_context_loader.dart';
import 'kb_storage.dart';

/// File-system implementation of [KbStorage].
///
/// Keeps the existing Markdown directory layout:
///
/// ```
/// kb/
///   questions/
///   answers/
///   notes/
///   topics/
///   areas/
///   people/
///   stats/
///   inbox/
///   INDEX.md
///   GRAPH.md
///   MEMORY.md
/// ```
class FileKbStorage implements KbStorage, KbAppendCapable, KbTombstoneCapable {
  final Directory kbDir;
  final KBContextLoader _contextLoader;

  FileKbStorage(this.kbDir) : _contextLoader = KBContextLoader();

  /// Frontmatter marker line written by [tombstoneEntity]. Chosen to be
  /// unambiguous (not part of any entity schema) and to survive a git
  /// union merge intact: even if another branch's modification of the same
  /// file is concatenated around it, the marker is still present, so
  /// [isTombstoneContent] keeps reporting the entity as deleted and the
  /// merge completes without manual resolution (delete wins).
  static const String tombstoneMarker = 'tombstone: true';

  static final RegExp _tombstoneRegex = RegExp(
    r'^tombstone:\s*true\s*$',
    multiLine: true,
  );

  /// True when [content] is a tombstone file (see [tombstoneEntity]).
  static bool isTombstoneContent(String content) =>
      _tombstoneRegex.hasMatch(content);

  /// Renders the tombstone body for [id]. Kept deliberately small and
  /// line-oriented so union merges of two tombstones (or a tombstone and a
  /// concurrent edit) stay well-formed and keep the marker.
  static String tombstoneContentFor(String id, String deletedAt) =>
      '''
---
id: $id
tombstone: true
deletedAt: $deletedAt
---

# Entity: $id

> 🪦 Deleted $deletedAt. This file is a tombstone: it is kept on disk
> instead of being unlinked so that git branches merge and rebase without
> delete/modify conflicts. Readers treat this entity as absent. Physical
> removal happens only during maintenance (`agent_memory memory gc`).
''';

  static const Map<String, String> _entityPrefix = {
    'question': 'q',
    'answer': 'a',
    'note': 'n',
  };

  static const Map<String, String> _entityDir = {
    'question': 'questions',
    'answer': 'answers',
    'note': 'notes',
  };

  @override
  FutureOr<void> initialize({bool clean = false}) {
    _contextLoader.initializeOutputDirectories(kbDir, clean: clean);
  }

  @override
  KBContext loadContext() => _contextLoader.loadContext(kbDir);

  @override
  String? readEntity(String type, String id) {
    final file = _entityFile(type, id);
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    // Tombstoned files stay on disk for conflict-free git merges; readers
    // must see the entity as absent.
    return isTombstoneContent(content) ? null : content;
  }

  @override
  void writeEntity(String type, String id, String content) {
    final file = _entityFile(type, id);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  @override
  void deleteEntity(String type, String id) {
    final file = _entityFile(type, id);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  void tombstoneEntity(String type, String id) {
    final file = _entityFile(type, id);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(tombstoneContentFor(id, currentUtcTimestamp()));
  }

  @override
  List<String> purgeTombstones() {
    final removed = <String>[];
    for (final type in _entityDir.keys) {
      for (final id in listEntityIds(type)) {
        final file = _entityFile(type, id);
        if (!file.existsSync()) continue;
        if (isTombstoneContent(file.readAsStringSync())) {
          file.deleteSync();
          removed.add(id);
        }
      }
    }
    return removed..sort();
  }

  @override
  List<String> listEntityIds(String type) {
    final dir = _entityDirectory(type);
    if (!dir.existsSync()) return const [];
    final prefix = _entityPrefix[type];
    if (prefix == null) return const [];
    final regex = RegExp('^${prefix}_(\\d+)(?:_[0-9a-f]{3,8})?\\.md\$');
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map((f) => f.uri.pathSegments.last)
        .where((name) => regex.hasMatch(name))
        .map((name) => name.replaceAll('.md', ''))
        .toList()
      ..sort();
  }

  @override
  String? readFile(String path) {
    final file = File('${_path(kbDir)}/$path');
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  }

  @override
  void writeFile(String path, String content) {
    final file = File('${_path(kbDir)}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  @override
  void appendFile(String path, String content) {
    final file = File('${_path(kbDir)}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content, mode: FileMode.append);
  }

  @override
  List<String> listFilePaths(String prefix) {
    final dir = Directory('${_path(kbDir)}/$prefix');
    if (!dir.existsSync()) return const [];
    final base = '${_path(kbDir)}/';
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map((f) => f.path.substring(base.length).replaceAll('\\', '/'))
        .toList()
      ..sort();
  }

  @override
  String describeLocation(String type, String id) => _entityFile(type, id).path;

  File _entityFile(String type, String id) {
    final dirName = _entityDir[type];
    if (dirName == null) throw ArgumentError('Unknown entity type: $type');
    return File('${_path(kbDir)}/$dirName/$id.md');
  }

  Directory _entityDirectory(String type) {
    final dirName = _entityDir[type];
    if (dirName == null) throw ArgumentError('Unknown entity type: $type');
    return Directory('${_path(kbDir)}/$dirName');
  }

  String _path(Directory dir) => dir.path;
}
