import 'dart:io';

String currentUtcTimestamp() {
  final now = DateTime.now().toUtc();
  return _toIso8601Utc(now);
}

String _toIso8601Utc(DateTime dt) {
  // yyyy-MM-ddTHH:mm:ssZ
  final iso = dt.toIso8601String();
  return iso.endsWith('Z') ? iso : '${iso}Z';
}

/// Best-effort read of a file modification time as an ISO-8601 UTC string.
String fileModifiedTimestamp(File file) {
  final stat = file.statSync();
  return _toIso8601Utc(stat.modified.toUtc());
}
