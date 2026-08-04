import 'dart:async';

import '../../models/memory_level.dart';
import '../../models/note.dart';
import '../../utils/date_utils.dart';
import '../kb_storage.dart';

/// Policy controlling automatic promotion and expiry of memory levels.
///
/// Raw records that survive for [rawToConsolidatedAfter] without contradiction
/// are promoted to consolidated. Consolidated records older than
/// [consolidatedToConceptAfter] are promoted to concept. Raw records that are
/// not confirmed within [rawExpiryAfter] can be removed.
class MemoryPromotionPolicy {
  final Duration rawToConsolidatedAfter;
  final Duration consolidatedToConceptAfter;
  final Duration rawExpiryAfter;

  const MemoryPromotionPolicy({
    this.rawToConsolidatedAfter = const Duration(days: 14),
    this.consolidatedToConceptAfter = const Duration(days: 90),
    this.rawExpiryAfter = const Duration(days: 30),
  });
}

/// Promotes or expires notes according to a [MemoryPromotionPolicy].
class MemoryLevelService {
  final KbStorage storage;
  final MemoryPromotionPolicy policy;
  final Future<void> Function(String id) deleteRecord;
  final Future<void> Function(Note note) writeNote;
  final Future<List<Note>> Function() listNotes;

  MemoryLevelService({
    required this.storage,
    required this.policy,
    required this.deleteRecord,
    required this.writeNote,
    required this.listNotes,
  });

  /// Promotes or expires notes according to [policy] and returns the
  /// number of records changed.
  ///
  /// Should be called periodically (e.g. from a background job) rather than
  /// on every write.
  Future<int> maintain() async {
    var changed = 0;
    final now = DateTime.parse(currentUtcTimestamp());

    for (final note in await listNotes()) {
      final date = _parseDate(note.date);
      if (date == null) continue;

      final age = now.difference(date);
      if (note.level == MemoryLevel.raw) {
        if (age > policy.rawExpiryAfter) {
          await deleteRecord(note.id);
          changed++;
          continue;
        }
        if (age > policy.rawToConsolidatedAfter) {
          await writeNote(note.copyWith(level: MemoryLevel.consolidated));
          changed++;
          continue;
        }
      }
      if (note.level == MemoryLevel.consolidated &&
          age > policy.consolidatedToConceptAfter) {
        await writeNote(note.copyWith(level: MemoryLevel.concept));
        changed++;
      }
    }
    return changed;
  }

  DateTime? _parseDate(String date) {
    if (date.isEmpty) return null;
    try {
      return DateTime.parse(date);
    } catch (_) {
      return null;
    }
  }
}
