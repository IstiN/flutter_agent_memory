// ignore: deprecated_member_use
import 'dart:html';

export 'web_storage_backend.dart';
import 'web_storage_backend.dart';

/// Browser `window.localStorage` implementation of [WebStorageBackend].
class HtmlWebStorageBackend implements WebStorageBackend {
  final Storage _storage;

  HtmlWebStorageBackend({Storage? storage})
    : _storage = storage ?? window.localStorage;

  @override
  String? getItem(String key) => _storage[key];

  @override
  void setItem(String key, String value) {
    _storage[key] = value;
  }

  @override
  void removeItem(String key) {
    _storage.remove(key);
  }

  @override
  List<String> keys() => _storage.keys.toList();

  @override
  void clear() {
    _storage.clear();
  }
}

WebStorageBackend createWebStorageBackend() => HtmlWebStorageBackend();
