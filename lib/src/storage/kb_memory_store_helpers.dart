part of 'kb_memory_store.dart';

Future<String?> _readExistingSummary(KBMemoryStore store) async {
  return (await store.storage.readFile('MEMORY.md'))?.trim();
}

bool _isRecordActiveAt(MemoryRecord record, DateTime asOf) {
  final note = record.note;
  if (note != null) {
    if (_hasValidityWindow(note)) {
      return _isNoteActiveAt(note, asOf);
    }
    return _isNoteActiveAt(note, asOf) && _isDateAtOrBefore(record.date, asOf);
  }
  return _isDateAtOrBefore(record.date, asOf);
}

bool _hasValidityWindow(Note note) {
  return (note.validFrom != null && note.validFrom!.isNotEmpty) ||
      (note.validUntil != null && note.validUntil!.isNotEmpty);
}

bool _isNoteActiveAt(Note note, DateTime asOf) {
  final from = _parseDate(note.validFrom);
  if (from != null && asOf.isBefore(from)) return false;

  final until = _parseDate(note.validUntil);
  if (until != null && asOf.isAfter(until)) return false;

  return true;
}

bool _isDateAtOrBefore(String? date, DateTime asOf) {
  final dt = _parseDate(date);
  if (dt == null) return true;
  return !dt.isAfter(asOf);
}

DateTime? _parseDate(String? date) {
  if (date == null || date.isEmpty) return null;
  try {
    return DateTime.parse(date);
  } catch (_) {
    return null;
  }
}

String _pad(int value) => value.toString().padLeft(4, '0');

class _Enriched {
  final String area;
  final List<String> topics;
  final List<String> tags;

  _Enriched({required this.area, required this.topics, required this.tags});
}
