import 'dart:io';

import 'file_kb_storage.dart';
import 'kb_storage.dart';

/// Creates a file-system [KbStorage] from a path string or a [Directory].
KbStorage createFileKbStorage(dynamic kbDir) {
  final directory = kbDir is String ? Directory(kbDir) : kbDir as Directory;
  return FileKbStorage(directory);
}
