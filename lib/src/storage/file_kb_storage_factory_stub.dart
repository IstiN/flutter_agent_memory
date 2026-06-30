import 'kb_storage.dart';

/// File-system storage is not available on the web.
KbStorage createFileKbStorage(dynamic kbDir) {
  throw UnsupportedError(
    'FileKbStorage is not available on web. Use InMemoryKbStorage, '
    'WebKbStorage, or HttpKbStorage instead.',
  );
}
