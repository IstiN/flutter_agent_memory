import 'dart:async';
import 'dart:io';

import '../models/kb_context.dart';
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
class FileKbStorage implements KbStorage {
  final Directory kbDir;
  final KBContextLoader _contextLoader;

  FileKbStorage(this.kbDir) : _contextLoader = KBContextLoader();

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
    return file.readAsStringSync();
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
  List<String> listEntityIds(String type) {
    final dir = _entityDirectory(type);
    if (!dir.existsSync()) return const [];
    final prefix = _entityPrefix[type];
    if (prefix == null) return const [];
    final regex = RegExp('^${prefix}_(\\d+)\\.md\$');
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
