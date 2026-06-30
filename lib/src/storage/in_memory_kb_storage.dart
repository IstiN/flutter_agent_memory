import 'dart:async';

import 'kb_storage.dart';
import 'kb_storage_context_mixin.dart';

/// In-memory implementation of [KbStorage].
///
/// Useful for tests, isolated sandboxing, and environments where a real
/// file system is not available. All content is kept in Dart maps and is
/// lost when the process ends.
class InMemoryKbStorage with KbStorageContextMixin implements KbStorage {
  final Map<String, Map<String, String>> _entities = {};
  final Map<String, String> _files = {};

  static const Map<String, String> _entityPrefix = {
    'question': 'q',
    'answer': 'a',
    'note': 'n',
  };

  @override
  FutureOr<void> initialize({bool clean = false}) {
    if (clean) {
      _entities.clear();
      _files.clear();
    }
  }

  @override
  String? readEntity(String type, String id) {
    return _entities[type]?[id];
  }

  @override
  void writeEntity(String type, String id, String content) {
    _entities.putIfAbsent(type, () => {})[id] = content;
  }

  @override
  void deleteEntity(String type, String id) {
    _entities[type]?.remove(id);
  }

  @override
  List<String> listEntityIds(String type) {
    final prefix = _entityPrefix[type];
    if (prefix == null) return const [];
    final regex = RegExp('^${prefix}_(\\d+)\$');
    final ids =
        _entities[type]?.keys.where((id) => regex.hasMatch(id)).toList() ?? [];
    ids.sort();
    return ids;
  }

  @override
  String? readFile(String path) => _files[path];

  @override
  void writeFile(String path, String content) {
    _files[path] = content;
  }

  @override
  List<String> listFilePaths(String prefix) {
    return _files.keys.where((path) => path.startsWith(prefix)).toList()
      ..sort();
  }

  @override
  String describeLocation(String type, String id) => 'memory://$type/$id';
}
