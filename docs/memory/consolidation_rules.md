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
out-of-order lines and takes the max cursor.

## Derivative files — rebuilt, never edited, never committed

- `GRAPH.md` — rebuilt deterministically (sorted nodes/edges) from the
  records by `buildGraph()`; deleting it and rebuilding yields identical
  bytes, so it is safe to keep out of git.
- `MEMORY.revision` — local concurrency accelerator; a fresh clone simply
  starts at generation 0.
- `INDEX.md`, `.last_maintenance` — local caches/markers.

`agent_memory memory init-git` writes the matching `.gitignore`.
