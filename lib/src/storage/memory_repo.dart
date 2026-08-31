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
///   `.last_maintenance`). Keeping them out of git removes the main source
///   of merge conflicts.
/// - `.gitattributes` — `DELETIONS.md merge=union`, so concurrent
///   tombstone appends from parallel branches merge line-wise.
class MemoryRepoInit {
  MemoryRepoInit(this.storage);

  static const gitignoreFile = '.gitignore';
  static const gitattributesFile = '.gitattributes';

  /// Derivative files excluded from git. Anything here must be
  /// rebuildable from the record files alone.
  static const derivativeFiles = <String>[
    'GRAPH.md',
    'MEMORY.revision',
    'INDEX.md',
    '.last_maintenance',
  ];

  /// Merge-driver assignments for conflict-prone files.
  static const mergeDriverLines = <String>['DELETIONS.md merge=union'];

  static const _gitignoreHeader =
      '# flutter_agent_memory derivatives - rebuilt from records, '
      'do not commit';
  static const _gitattributesHeader =
      '# flutter_agent_memory merge drivers';

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
