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
