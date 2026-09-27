import 'kb_storage.dart';

/// Outcome of [MemoryRepoInit.ensureGitSupport].
class MemoryRepoInitResult {
  const MemoryRepoInitResult({
    required this.gitignoreUpdated,
    required this.gitattributesUpdated,
  });

  /// Whether `.gitignore` was created or gained new lines.
  final bool gitignoreUpdated;

  /// Whether `.gitattributes` was created or gained new lines.
  final bool gitattributesUpdated;

  /// True when both files already contained every required line.
  bool get alreadyConfigured => !gitignoreUpdated && !gitattributesUpdated;
}

/// Prepares a memory store directory to live inside a git repository.
///
/// Writes (idempotently, preserving user content):
///
/// - `.gitignore` — derivative files that are rebuilt from records and
///   must not be committed (`GRAPH.md`, `MEMORY.revision`, `INDEX.md`,
///   `.last_maintenance`, `.last_deletions`). Keeping them out of git
///   removes the main source of merge conflicts.
/// - `.gitattributes` — union merge drivers, so concurrent modifications
///   of the same file from parallel branches merge line-wise instead of
///   blocking with a content conflict:
///   - `DELETIONS.md merge=union` — tombstone ledger appends.
///   - `questions|answers|notes/*.md merge=union` — entity files.
///     Deletions never unlink entity files (they rewrite them in place as
///     tombstones, see [KbTombstoneCapable]), so git never sees a
///     delete/modify conflict for them; union resolves the remaining
///     modify/modify case (e.g. an update on one branch, a tombstone or
///     another update on the other) deterministically — the tombstone
///     marker survives the union, so delete wins.
class MemoryRepoInit {
  MemoryRepoInit(this.storage);

  static const gitignoreFile = '.gitignore';
  static const gitattributesFile = '.gitattributes';

  /// Derivative files excluded from git. Anything here must be
  /// rebuildable from the record files alone or be purely local state.
  static const derivativeFiles = <String>[
    'GRAPH.md',
    'MEMORY.revision',
    'INDEX.md',
    '.last_maintenance',
    // Local consolidation progress (set-difference marker for deleted/
    // files) — each clone tracks its own; merging it would lose entries.
    '.last_deletions',
  ];

  /// Merge-driver assignments for conflict-prone files.
  static const mergeDriverLines = <String>[
    'DELETIONS.md merge=union',
    'questions/*.md merge=union',
    'answers/*.md merge=union',
    'notes/*.md merge=union',
    // Safety net: same-record deletions from parallel branches write the
    // identical file (deterministic content), so add/add merges are
    // trivial; the driver covers the exotic legacy-id collision where two
    // different texts share one id.
    'deleted/*.md merge=union',
  ];

  static const _gitignoreHeader =
      '# flutter_agent_memory derivatives - rebuilt from records, '
      'do not commit';
  static const _gitattributesHeader = '# flutter_agent_memory merge drivers';

  final KbStorage storage;

  /// Ensures `.gitignore` and `.gitattributes` exist with every required
  /// line. Appends only missing lines; never rewrites or removes existing
  /// content. Safe to run repeatedly.
  Future<MemoryRepoInitResult> ensureGitSupport() async {
    final gitignoreUpdated = await _ensureLines(gitignoreFile, const [
      _gitignoreHeader,
      ...derivativeFiles,
    ]);
    final gitattributesUpdated = await _ensureLines(gitattributesFile, const [
      _gitattributesHeader,
      ...mergeDriverLines,
    ]);
    return MemoryRepoInitResult(
      gitignoreUpdated: gitignoreUpdated,
      gitattributesUpdated: gitattributesUpdated,
    );
  }

  Future<bool> _ensureLines(String name, List<String> required) async {
    final existing = (await storage.readFile(name)) ?? '';
    final lines = existing.split('\n').map((l) => l.trimRight()).toList();
    final present = lines.map((l) => l.trim()).toSet();
    final missing = required.where((l) => !present.contains(l.trim()));
    if (missing.isEmpty) return false;
    final buffer = StringBuffer(existing);
    if (existing.isNotEmpty && !existing.endsWith('\n')) buffer.writeln();
    for (final line in missing) {
      buffer.writeln(line);
    }
    await storage.writeFile(name, buffer.toString());
    return true;
  }
}
