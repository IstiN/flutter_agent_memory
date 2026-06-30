import 'dart:async';

import '../kb_storage.dart';
import '../kb_storage_context_mixin.dart';
import 'web_storage_backend.dart'
    if (dart.library.html) 'web_storage_backend_html.dart';

/// Browser-storage implementation of [KbStorage].
///
/// Stores all entity and structure Markdown content in `window.localStorage`
/// (or any other [WebStorageBackend]). Keys are prefixed with `fam:` to avoid
/// collisions.
///
/// On non-web platforms the default backend throws [UnsupportedError], so this
/// class can still be imported and referenced in shared code but only used at
/// runtime on the web.
class WebKbStorage with KbStorageContextMixin implements KbStorage {
  final WebStorageBackend _backend;

  static const String _prefix = 'fam:';
  static const Map<String, String> _entityPrefix = {
    'question': 'q',
    'answer': 'a',
    'note': 'n',
  };

  WebKbStorage({WebStorageBackend? backend})
    : _backend = backend ?? createWebStorageBackend();

  @override
  FutureOr<void> initialize({bool clean = false}) {
    if (clean) {
      for (final key in _backend.keys()) {
        if (key.startsWith(_prefix)) _backend.removeItem(key);
      }
    }
  }

  @override
  String? readEntity(String type, String id) {
    return _backend.getItem(_entityKey(type, id));
  }

  @override
  void writeEntity(String type, String id, String content) {
    _backend.setItem(_entityKey(type, id), content);
  }

  @override
  void deleteEntity(String type, String id) {
    _backend.removeItem(_entityKey(type, id));
  }

  @override
  List<String> listEntityIds(String type) {
    final prefix = _entityPrefix[type];
    if (prefix == null) return const [];
    final keyPrefix = '$_prefix$type:';
    final regex = RegExp('^$keyPrefix(${prefix}_(\\d+))\$');
    return _backend
        .keys()
        .where((key) => key.startsWith(keyPrefix))
        .map((key) {
          final match = regex.firstMatch(key);
          return match?.group(1);
        })
        .whereType<String>()
        .toList()
      ..sort();
  }

  @override
  String? readFile(String path) => _backend.getItem(_fileKey(path));

  @override
  void writeFile(String path, String content) {
    _backend.setItem(_fileKey(path), content);
  }

  @override
  List<String> listFilePaths(String prefix) {
    final keyPrefix = '${_prefix}file:$prefix';
    return _backend
        .keys()
        .where((key) => key.startsWith(keyPrefix))
        .map((key) => key.substring('${_prefix}file:'.length))
        .toList()
      ..sort();
  }

  @override
  String describeLocation(String type, String id) => 'web://$type/$id';

  String _entityKey(String type, String id) => '$_prefix$type:$id';

  String _fileKey(String path) => '${_prefix}file:$path';
}
