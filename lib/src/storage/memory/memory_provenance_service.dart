import 'dart:async';

import '../../models/memory_level.dart';
import '../../models/note.dart';
import '../../utils/memory_utils.dart';

/// Creates cross-scope note copies with a provenance marker.
class MemoryProvenanceService {
  /// Prepares a copy of [note] annotated with its [sourceScope].
  ///
  /// The copied note receives a `(said in <sourceScope>)` suffix so the
  /// receiving scope can evaluate the source of the fact. Returns null if
  /// an equivalent note already exists in the target scope.
  static Future<Note?> prepareCopy(
    Note note,
    String sourceScope,
    Future<bool> Function(String normalized) existsInTarget,
  ) async {
    final source = sourceScope.replaceAll(RegExp(r'[\r\n()]+'), ' ').trim();
    final provenance = source.isNotEmpty ? source : 'a shared scope';

    final normalized = normalizeMemoryText(note.text);
    if (await existsInTarget(normalized)) return null;

    final text =
        note.text.endsWith('.') ||
            note.text.endsWith('!') ||
            note.text.endsWith('?')
        ? '${note.text} (said in $provenance)'
        : '${note.text}. (said in $provenance)';

    return note.copyWith(
      text: text,
      level: MemoryLevel.raw,
      // Clear id so the target store assigns its own.
      id: '',
    );
  }
}
