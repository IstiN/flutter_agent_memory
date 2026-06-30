String currentUtcTimestamp() {
  final now = DateTime.now().toUtc();
  return _toIso8601Utc(now);
}

String _toIso8601Utc(DateTime dt) {
  // yyyy-MM-ddTHH:mm:ssZ
  final iso = dt.toIso8601String();
  return iso.endsWith('Z') ? iso : '${iso}Z';
}
