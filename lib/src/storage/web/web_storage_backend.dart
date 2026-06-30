/// Backend abstraction for browser storage (localStorage / sessionStorage).
///
/// The default implementation is a stub for non-web platforms. The real
/// `window.localStorage` backend is provided by the conditional import
/// `web_storage_backend_html.dart`.
abstract class WebStorageBackend {
  String? getItem(String key);
  void setItem(String key, String value);
  void removeItem(String key);
  List<String> keys();
  void clear();
}

WebStorageBackend createWebStorageBackend() => _UnsupportedWebStorage();

class _UnsupportedWebStorage implements WebStorageBackend {
  Never _throw() => throw UnsupportedError(
    'WebStorageBackend is only available on web platforms. '
    'Import the package with dart.library.html enabled.',
  );

  @override
  String? getItem(String key) => _throw();

  @override
  void setItem(String key, String value) => _throw();

  @override
  void removeItem(String key) => _throw();

  @override
  List<String> keys() => _throw();

  @override
  void clear() => _throw();
}
