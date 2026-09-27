import 'dart:io';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:test/test.dart';

import '../fake_llm_provider.dart';

bool _gitAvailable() {
  try {
    return Process.runSync('git', ['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Acceptance test for issue #1: two concurrent agents can delete and
/// modify the same memory file and a rebase/merge completes with zero
/// manual conflict resolution.
///
/// Runs against the real `git` binary; skipped when git is unavailable.
void main() {
  final gitAvailable = _gitAvailable();
  final git = gitAvailable ? 'git' : null;

  late Directory repo;

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('kb_gitconflict_');
  });

  tearDown(() async {
    if (repo.existsSync()) await repo.delete(recursive: true);
  });

  Future<ProcessResult> gitRun(
    String repoPath,
    List<String> args, {
    String? branch,
  }) async {
    final result = await Process.run(
      git!,
      ['-C', repoPath, ...args],
      environment: {
        'GIT_AUTHOR_NAME': 'Test',
        'GIT_AUTHOR_EMAIL': 'test@example.com',
        'GIT_COMMITTER_NAME': 'Test',
        'GIT_COMMITTER_EMAIL': 'test@example.com',
      },
    );
    return result;
  }

  KBMemoryStore store(String path) => KBMemoryStore.file(
    path,
    provider: FakeLlmProvider(const {}),
    source: 'test',
  );

  group('delete/modify across branches (git-backed)', () {
    test(
      'tombstone on one branch + edit on the other rebases cleanly',
      () async {
        // Bootstrap a committed memory store.
        final s = store(repo.path);
        final note = await s.addNote(text: 'Shared fact across branches.');
        await MemoryRepoInit(s.storage).ensureGitSupport();
        expect(await gitRun(repo.path, ['init', '-q']), isNotNull);
        // Pin the branch name regardless of init.defaultBranch config.
        await gitRun(repo.path, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
        await gitRun(repo.path, ['add', '-A']);
        final baseCommit = await gitRun(repo.path, [
          'commit',
          '-q',
          '-m',
          'base',
        ]);
        expect(baseCommit.exitCode, 0, reason: baseCommit.stderr as String?);

        // Branch A: agent deletes the note (tombstone-in-place).
        await gitRun(repo.path, ['checkout', '-q', '-b', 'agent-a']);
        final storeA = store(repo.path);
        expect(await storeA.deleteRecord(note.id), isTrue);
        await gitRun(repo.path, ['add', '-A']);
        final commitA = await gitRun(repo.path, [
          'commit',
          '-q',
          '-m',
          'agent A deletes the note',
        ]);
        expect(commitA.exitCode, 0, reason: commitA.stderr as String?);

        // Branch B (main): another agent edits the same note file.
        await gitRun(repo.path, ['checkout', '-q', 'main']);
        final storeB = store(repo.path);
        await storeB.updateRecord(
          note.id,
          text: 'Shared fact across branches, refined.',
        );
        await gitRun(repo.path, ['add', '-A']);
        final commitB = await gitRun(repo.path, [
          'commit',
          '-q',
          '-m',
          'agent B edits the note',
        ]);
        expect(commitB.exitCode, 0, reason: commitB.stderr as String?);

        // Rebase B onto A — must complete with zero conflict resolution.
        final rebase = await gitRun(repo.path, ['rebase', 'agent-a']);
        expect(
          rebase.exitCode,
          0,
          reason: 'stdout: ${rebase.stdout}\nstderr: ${rebase.stderr}',
        );
        final status = await gitRun(repo.path, ['status', '--porcelain']);
        expect((status.stdout as String).trim(), isEmpty);

        // Delete won deterministically: the file is a tombstone and no
        // reader sees the record.
        final file = File('${repo.path}/notes/${note.id}.md');
        expect(file.existsSync(), isTrue);
        expect(
          FileKbStorage.isTombstoneContent(file.readAsStringSync()),
          isTrue,
        );
        final merged = store(repo.path);
        expect(await merged.isDeleted(note.id), isTrue);
        final records = await merged.list();
        expect(records.map((r) => r.id), isNot(contains(note.id)));
      },
      skip: git == null ? 'git binary not available' : false,
    );

    test(
      'independent deletions from two branches merge cleanly and none are lost',
      () async {
        final s = store(repo.path);
        final noteA = await s.addNote(text: 'Fact deleted by agent A.');
        final noteB = await s.addNote(text: 'Fact deleted by agent B.');
        await MemoryRepoInit(s.storage).ensureGitSupport();
        await gitRun(repo.path, ['init', '-q']);
        await gitRun(repo.path, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
        await gitRun(repo.path, ['add', '-A']);
        await gitRun(repo.path, ['commit', '-q', '-m', 'base']);

        // Agent A deletes noteA (and consolidates: the marker is local
        // only, so nothing it processed is lost for other clones).
        await gitRun(repo.path, ['checkout', '-q', '-b', 'agent-a']);
        final storeA = store(repo.path);
        expect(await storeA.deleteRecord(noteA.id), isTrue);
        final serviceA = MemoryDeletionService(storeA.storage);
        await serviceA.markDeletionsProcessed(
          await serviceA.unprocessedDeletions(),
        );
        await gitRun(repo.path, ['add', '-A']);
        await gitRun(repo.path, ['commit', '-q', '-m', 'A deletes noteA']);

        // Agent B works in a fresh clone of main: its local marker does not
        // exist yet (the marker never travels through git).
        await gitRun(repo.path, ['checkout', '-q', 'main']);
        File('${repo.path}/.last_deletions').deleteSync();
        final storeB = store(repo.path);
        expect(await storeB.deleteRecord(noteB.id), isTrue);
        final serviceB = MemoryDeletionService(storeB.storage);
        // B only sees its own deletion — noteA is not in its clone.
        final pendingB = await serviceB.unprocessedDeletions();
        expect(pendingB.map((d) => d.id), [noteB.id]);
        await serviceB.markDeletionsProcessed(pendingB);
        await gitRun(repo.path, ['add', '-A']);
        await gitRun(repo.path, ['commit', '-q', '-m', 'B deletes noteB']);

        // Both branches only CREATED files (tombstone rewrite + deleted/
        // record + local gitignored marker) — merge must be trivially clean.
        final merge = await gitRun(repo.path, [
          'merge',
          '--no-edit',
          'agent-a',
        ]);
        expect(
          merge.exitCode,
          0,
          reason: 'stdout: ${merge.stdout}\nstderr: ${merge.stderr}',
        );

        final merged = store(repo.path);
        expect(await merged.isDeleted(noteA.id), isTrue);
        expect(await merged.isDeleted(noteB.id), isTrue);
        expect(await merged.hasDeletedText('Fact deleted by agent A.'), isTrue);
        expect(await merged.hasDeletedText('Fact deleted by agent B.'), isTrue);
        // A's deletion still surfaces for consolidation in this clone even
        // though B already consolidated its own — the set difference cannot
        // lose entries across branches (the legacy seq cursor would have).
        final pending = await MemoryDeletionService(
          merged.storage,
        ).unprocessedDeletions();
        expect(pending.map((d) => d.id), [noteA.id]);
      },
      skip: git == null ? 'git binary not available' : false,
    );

    test(
      'delete on both branches merges cleanly through the union driver',
      () async {
        final s = store(repo.path);
        final note = await s.addNote(text: 'Delete me everywhere.');
        await MemoryRepoInit(s.storage).ensureGitSupport();
        await gitRun(repo.path, ['init', '-q']);
        await gitRun(repo.path, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
        await gitRun(repo.path, ['add', '-A']);
        await gitRun(repo.path, ['commit', '-q', '-m', 'base']);

        await gitRun(repo.path, ['checkout', '-q', '-b', 'agent-a']);
        expect(await store(repo.path).deleteRecord(note.id), isTrue);
        await gitRun(repo.path, ['add', '-A']);
        await gitRun(repo.path, ['commit', '-q', '-m', 'delete on A']);

        await gitRun(repo.path, ['checkout', '-q', 'main']);
        await gitRun(repo.path, ['checkout', '-q', '-b', 'agent-b']);
        expect(await store(repo.path).deleteRecord(note.id), isTrue);
        await gitRun(repo.path, ['add', '-A']);
        await gitRun(repo.path, ['commit', '-q', '-m', 'delete on B']);

        final merge = await gitRun(repo.path, [
          'merge',
          '--no-edit',
          'agent-a',
        ]);
        expect(
          merge.exitCode,
          0,
          reason: 'stdout: ${merge.stdout}\nstderr: ${merge.stderr}',
        );
        final file = File('${repo.path}/notes/${note.id}.md');
        expect(file.existsSync(), isTrue);
        expect(
          FileKbStorage.isTombstoneContent(file.readAsStringSync()),
          isTrue,
        );
        expect(await store(repo.path).isDeleted(note.id), isTrue);
      },
      skip: git == null ? 'git binary not available' : false,
    );
  });
}
