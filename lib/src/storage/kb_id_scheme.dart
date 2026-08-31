import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../utils/memory_utils.dart';

/// Merge-friendly record id allocation for git-backed memory stores.
///
/// New records get ids of the form `<prefix>_<index>_<hash>`
/// (e.g. `n_0447_a1b2`): the sequential index is preserved, and a short
/// content-hash suffix makes index collisions between parallel git branches
/// harmless — two branches that both allocate index 447 produce distinct
/// files (`n_0447_a1b2.md`, `n_0447_c3d4.md`) that merge by union.
///
/// Two branches capturing the *same* text at the same index produce the
/// *same* id, so git merges them cleanly. Legacy ids without a suffix
/// (`n_0001`) remain valid forever; no migration of existing files.
abstract final class MemoryIdScheme {
  /// Number of leading md5 hex characters used as the id suffix.
  static const int idHashLength = 4;

  /// Matches both legacy (`n_0001`) and suffixed (`n_0001_a1b2`) ids.
  static final RegExp idPattern = RegExp(
    r'^([qan])_(\d+)(?:_([0-9a-f]{3,8}))?$',
  );

  /// Allocates a merge-friendly id for a record of type [prefix]
  /// (`q`/`a`/`n`) with sequential [index] and primary [text].
  ///
  /// [answersQuestion] is an optional discriminator mixed into the hash of
  /// answers, so identical answer texts to different questions never share
  /// an id when they collide on the same index.
  static String allocate(
    String prefix,
    int index,
    String text, {
    String? answersQuestion,
  }) =>
      '${prefix}_${_pad(index)}_'
      '${hashSuffix(text, answersQuestion: answersQuestion)}';

  /// Computes the hash suffix for a record's primary [text].
  ///
  /// The text is normalized via [normalizeMemoryText] first — the same
  /// canon used by dedup and tombstones — so whitespace/casing differences
  /// do not change the id. Frontmatter is never hashed: ids stay stable
  /// when a record is enriched (relations, access counts, dates).
  static String hashSuffix(String text, {String? answersQuestion}) {
    final discriminator = answersQuestion != null && answersQuestion.isNotEmpty
        ? '|q=$answersQuestion'
        : '';
    final input = '${normalizeMemoryText(text)}$discriminator';
    return md5.convert(utf8.encode(input)).toString().substring(
      0,
      idHashLength,
    );
  }

  /// Extracts the sequential index from a legacy or suffixed id.
  ///
  /// Returns `null` for ids that match neither format.
  static int? parseIndex(String id) {
    final match = idPattern.firstMatch(id);
    return match == null ? null : int.tryParse(match.group(2)!);
  }

  /// Whether [id] is a legacy id without a hash suffix (`n_0001`).
  static bool isLegacy(String id) {
    final match = idPattern.firstMatch(id);
    return match != null && match.group(3) == null;
  }

  /// Whether [id] is a valid record id in either format.
  static bool isValid(String id) => idPattern.hasMatch(id);

  static String _pad(int value) => value.toString().padLeft(4, '0');
}
