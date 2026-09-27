/// Memory-management policies as string constants.
///
/// These mirror the canonical markdown documents in `docs/memory/` and are
/// kept in sync by `test/policy/memory_policy_test.dart`. Hosted consumers
/// (e.g. agent harnesses installed from pub.dev) can embed the policies in
/// prompts without file access.
abstract final class MemoryPolicy {
  /// Contents of `docs/memory/memory_add_policy.md` (trimmed).
  static const String memoryAddPolicy = r'''
# `memory_add` policy

## What to store

Store only **durable** facts — things that must survive across sessions:

- project conventions, architecture decisions and their rationale;
- user preferences, habits, environment facts;
- key discoveries that were expensive to learn (non-obvious behaviour,
  gotchas, working configurations).

Do **not** store task progress, transient state, or anything derivable
from the repository itself (file contents, git history, current diffs).

## The supersede rule

Facts age. When a problem is **solved** or a fact **changes**:

1. delete the outdated record (`memory_delete` by id or exact text —
   deletions are tombstoned, so the old text cannot be re-captured);
2. add the new fact as a fresh record.

Never leave temporary difficulties, workarounds, or "currently broken"
notes in memory forever. A memory full of solved problems actively
misleads future sessions. If you used a record to fix something, that
record's job is done — supersede it.

Before adding anything, `memory_search` for an existing record on the
topic: update (delete + add) instead of duplicating.

## Scope discipline

- **project scope** (default) lives in the project's memory directory and
  is **public**: it is committed to git and shared with everyone who
  clones the repository. Never store secrets, credentials, personal data,
  or anything you would not put in a public commit message.
- **user scope** is global and private to the user's machine. Use it for
  cross-project preferences and facts about the user.

## Style

- One fact per record, concise and self-contained (readable without the
  conversation that produced it).
- Add concrete tags (see [tag_taxonomy.md](tag_taxonomy.md)).
- Prefer facts with staying power: "tests run with `--exclude-tags
  integration`" outlives "I am currently fixing the test suite".
''';

  /// Contents of `docs/memory/tag_taxonomy.md` (trimmed).
  static const String tagTaxonomy = r'''
# Tag taxonomy

## System tags (managed by the framework, never hand-edit)

- `#question`, `#answer`, `#note` — entity-type markers, exactly one per
  record. Emitted on every render; user tags live alongside them.
- `#source_<name>` — provenance marker: which source (transcript, agent,
  import) produced the record. One per record.

System tags are preserved automatically when a record is re-rendered
(relations added, promoted, accessed). Do not add or remove them manually.

## Free tags

- Lowercase, 1–3 words, hyphenated (`state-management`, `github-actions`).
- Concrete: name tools, frameworks, services, concepts from the record
  itself. No generic tags (`question`, `issue`, `help`, `misc`).
- Maximum ~5 per record; fewer, sharper tags beat exhaustive lists.
- **Reuse before inventing**: search the existing tag list first and
  prefer a tag that already exists when it genuinely matches. Tag growth
  without reuse destroys searchability.
- Topics are broader than tags: 1–3 themes of the subject matter, while
  tags are the concrete keywords.

## How tags are used

Search generates candidate tags from the query (via LLM) and matches them
against record tags *and* keywords, then merges and ranks results. A
record with precise, reused tags is findable; a record with novel or
generic tags is not.
''';

  /// Contents of `docs/memory/consolidation_rules.md` (trimmed).
  static const String consolidationRules = r'''
# Consolidation rules

## The revision contract

`MEMORY.md` is written by consolidation and guarded by a revision hash.
Every caller must follow:

```dart
final revision = await store.readMemoryRevision();
try {
  await store.consolidate(expectedRevisionHash: revision.hash);
} on ConcurrentRevisionException {
  // Records changed under you (a delete, another consolidate).
  // Re-read and retry later — never write MEMORY.md unconditionally.
}
```

A consolidation that started before a deletion must fail with
`ConcurrentRevisionException`, not resurrect the deleted content. The
revision service mixes a generation counter (`MEMORY.revision`) into the
hash; when the file is absent (fresh clone), the hash is derived from the
MEMORY.md content alone and still protects the read-modify-write cycle.

## Tombstones during consolidation

Deletions are append-only lines in `DELETIONS.md`. Consolidation receives
cleanup notices for tombstones newer than the `consolidatedUpTo` cursor
and must remove claims sourced from deleted records; after a successful
write the cursor advances and those notices are not repeated. Tombstoned
text is never re-captured while its ledger entry exists
(`respectTombstones`, on by default).

`DELETIONS.md` merges across git branches by union
(`DELETIONS.md merge=union` in `.gitattributes`, written by
`agent_memory memory init-git`); the parser tolerates duplicate and
out-of-order lines and takes the max cursor. The ledger is legacy
compatibility for pre-`deleted/` stores; new deletions are recorded in the
`deleted/` directory below and consolidation no longer uses the cursor —
a global `seq` counter cannot survive branching (deletions merged in
after the cursor was written would be silently skipped).

## Entity files: tombstones, never unlinks

A deletion never unlinks the entity file. On the git-backed file storage
the file is rewritten in place as a tombstone (`tombstone: true` in the
frontmatter); readers treat tombstoned entities as absent. Because git
never sees a file deletion for `questions/answers/notes/*.md`, the classic
delete/modify conflict — one branch deletes a record, another edits it —
cannot occur. The union merge drivers for the entity files (also written
by `agent_memory memory init-git`) resolve the remaining modify/modify
case line-wise; the tombstone marker survives a union merge, so delete
wins deterministically and no rebase or merge ever needs manual
resolution for memory churn.

Tombstone files accumulate until `agent_memory memory gc`
(`store.purgeTombstones()`) runs during a maintenance window when no
concurrent agent writes memory — purging re-introduces file deletions
into git history, which is safe only when nothing else touches the same
files. The ledger above is the durable record of what was deleted, so
purging loses no history and tombstoned ids are never reused.

## The deleted/ directory — the conflict-free deletion record

Every deletion also creates one small file in `deleted/`, named
`<id>_<fingerprint8>.md`, with deterministic content (no wall-clock
fields): two branches deleting the same record produce the identical
file — git merges them trivially — and different deletions are
independent files that never interact. Recording a deletion is only ever
a file *creation*, so concurrent agents on different branches can never
conflict, not even through the merge driver.

`isDeleted(id)` and `hasDeletedText(text)` are answered from `deleted/`
(with the legacy ledger as a fallback for old stores). Because the files
are never rotated, capture-time deduplication keeps working for the full
deletion history, independent of ledger compaction.

Consolidation progress is a local set difference, not a shared cursor:
`.last_deletions` (gitignored, written by `agent_memory memory init-git`)
lists the fingerprints the local consolidation has already been warned
about; `unprocessedDeletions()` returns `deleted/` files whose
fingerprint is missing from the marker. Deletions that merge in from
other branches afterwards are still reported on the next run — cleanup
notices can never be lost across branches.

## Derivative files — rebuilt, never edited, never committed

- `GRAPH.md` — rebuilt deterministically (sorted nodes/edges) from the
  records by `buildGraph()`; deleting it and rebuilding yields identical
  bytes, so it is safe to keep out of git.
- `MEMORY.revision` — local concurrency accelerator; a fresh clone simply
  starts at generation 0.
- `INDEX.md`, `.last_maintenance` — local caches/markers.

`agent_memory memory init-git` writes the matching `.gitignore`.
''';
}
