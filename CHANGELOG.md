# Changelog

## 0.2.3

- **Per-record `deleted/` deletion record — concurrent agents can never
  conflict on deletions, and cleanup notices can never be lost across
  branches.** Every deletion now also creates one small deterministic
  file `deleted/<id>_<fingerprint8>.md` (no wall-clock fields): two
  branches deleting the same record produce the identical file (git
  merges them trivially), different deletions are independent files.
  Recording a deletion is only ever a file *creation* — there is no
  shared mutable file and no global `seq` counter anymore.
- **Consolidation progress is a local set difference, not a shared
  cursor.** New `unprocessedDeletions()` /
  `markDeletionsProcessed()` pair: the gitignored `.last_deletions`
  marker (added to `MemoryRepoInit` derivatives, union-safety
  `deleted/*.md merge=union` added to merge drivers) lists the
  fingerprints already fed to the local consolidation. The legacy
  `DELETIONS.md` `consolidatedUpTo` cursor is a global counter that does
  not survive branching — deletions merged in after the cursor was
  written were silently never reported to consolidation (deleted facts
  could resurrect in `MEMORY.md`). `pendingDeletions`/`markConsolidated`
  remain for backward compatibility; `consolidate()` uses the new API.
- `isDeleted` / `hasDeletedText` answer from `deleted/` first, with the
  legacy ledger as fallback for pre-0.2.3 stores; `deleted/` files are
  never rotated, so capture-time deduplication covers the full deletion
  history.
- New real-git acceptance test: independent deletions from two branches
  (each already consolidated locally) merge cleanly, and the deletion
  from the other branch still surfaces for consolidation afterwards.

## 0.2.2

- **Conflict-free deletions (issue #1).** Deleting a record no longer
  unlinks its entity file. On the git-backed file storage a deletion now
  rewrites the file in place as a **tombstone** (frontmatter marker
  `tombstone: true`), so git never sees a file deletion for
  `questions/answers/notes/*.md` and the classic **delete/modify conflict
  that blocked automated rebases cannot occur by construction**. Both
  sides of a merge only ever modify files.
- **Union merge drivers for entity files.** `MemoryRepoInit` now writes
  `questions/*.md merge=union`, `answers/*.md merge=union` and
  `notes/*.md merge=union` into `.gitattributes` (alongside the existing
  `DELETIONS.md merge=union`). The remaining modify/modify case (e.g. an
  update on one branch, a tombstone on the other) resolves line-wise; the
  tombstone marker survives a union merge, so **delete wins
  deterministically** and no rebase/merge ever needs manual resolution
  for memory churn.
- **New `KbTombstoneCapable` interface** implemented by `FileKbStorage`:
  `tombstoneEntity` (rewrite-in-place) and `purgeTombstones` (physical
  removal). `KbStorage.readEntity` on the file backend reports tombstoned
  entities as absent, so all readers (list, search, graph, overview) skip
  them. Storages without the capability keep the previous physical-delete
  behaviour.
- **New `agent_memory memory gc` command** (and
  `KBMemoryStore.purgeTombstones`) physically removes tombstone files.
  Run it only during maintenance when no concurrent agent writes memory:
  purging re-introduces file deletions into git history. The `DELETIONS.md`
  ledger is the durable deletion record, so purging loses no history.
- Tombstoned ids still occupy their index — record ids are never reused
  even after a purge.
- Acceptance coverage with the real `git` binary
  (`test/storage/delete_modify_conflict_test.dart`): tombstone-on-one-branch
  + edit-on-the-other rebases with zero conflicts; delete-on-both-branches
  merges cleanly through the union driver.

## 0.2.1

- **Fix: append-only deletion ledger (critical).** `DELETIONS.md` writes
  are now strictly append-only — a delete or a consolidation-cursor update
  adds lines without rewriting existing content. Previously a
  read-modify-write cycle could (a) clobber the whole ledger when its
  content failed to parse (e.g. an older or foreign format after a
  0.1.x → 0.2.0 upgrade) and (b) lose tombstones under concurrent deletes
  (last writer wins). The ledger is compacted only after growing past
  twice `maxLedgerEntries`, and compaction refuses to touch content it
  cannot parse.
- **`markConsolidated(seq)` is append-only too**: it appends a new
  `consolidatedUpTo:` line (the parser takes the max over all of them, and
  git merges them by union) instead of rewriting the file.
- **New `KbAppendCapable` interface + `KbStorageAppend` extension.**
  Storages with native append (implemented by `FileKbStorage` via
  `FileMode.append`) get atomic-enough appends so concurrent deletes both
  land; other backends fall back to documented best-effort
  read-modify-write. Custom `KbStorage` implementations should implement
  `KbAppendCapable` for the same guarantee.
- **Tolerant ledger parsing**: entries without a `type:` field derive it
  from the id prefix; missing fingerprints are recomputed from the text.

## 0.2.0

- **Git-backed memory.** Memory stores are now designed to live inside a
  git repository: cloning the repo gives every agent the full memory.
  - **Merge-friendly record ids.** New records get
    `<prefix>_<index>_<hash>` ids (`n_0447_a1b2`): the sequential index
    stays, plus a 4-char md5 suffix of the normalized record text (with an
    `answersQuestion` discriminator for answers). Parallel branches that
    allocate the same index produce distinct files that merge by union;
    branches that capture the same text produce the same id and merge
    cleanly. Legacy ids (`n_0001`) remain valid forever — no migration,
    existing stores keep working unchanged.
  - **Deterministic derivatives.** `GRAPH.md` is rebuilt with sorted
    nodes/edges and no wall-clock timestamps — rebuilding from the same
    records yields byte-identical output, so it can stay uncommitted.
    `MEMORY.revision` is strictly local (absent on a fresh clone = legacy
    content-hash path).
  - **Union-mergeable deletion ledger.** `DELETIONS.md` is a formalized
    append-only line log (the conflicting `count:` header line is gone);
    the parser tolerates git `merge=union` output: duplicate lines are
    collapsed by (seq, id), entries are sorted by seq, and the
    consolidation cursor is the max over all headers.
  - **`MemoryRepoInit` + `agent_memory memory init-git`** write
    `.gitignore` (derivatives: `GRAPH.md`, `MEMORY.revision`, `INDEX.md`,
    `.last_maintenance`) and `.gitattributes`
    (`DELETIONS.md merge=union`) into the store directory, idempotently
    and preserving user content.
- **Memory policy documents** in `docs/memory/` — `memory_add_policy.md`
  (durable facts only, the supersede rule: solved problems are deleted and
  re-added, project scope is public), `tag_taxonomy.md`,
  `consolidation_rules.md` — mirrored as Dart string constants in the new
  public `MemoryPolicy` class (sync enforced by tests) so hosted consumers
  can embed them in prompts without file access.
- New public API: `MemoryIdScheme` (allocate/hashSuffix/parseIndex/
  isLegacy/isValid), `MemoryRepoInit` (+ `MemoryRepoInitResult`),
  `MemoryPolicy`.

## 0.1.1

- Export `MemoryDeletionService` (+ `MemoryDeletion`, `MemoryDeleteResult`)
  and `MemoryRevisionService` (+ `MemoryRevision`,
  `ConcurrentRevisionException`) from the public barrels
  (`lib/flutter_agent_memory.dart` / `lib/storage.dart`) so consumers can use
  the deletion ledger (`pendingDeletions` / `markConsolidated`) and the
  consolidate revision contract directly.

## 0.1.0

- **`memory_delete` (safe tombstone deletion).**
  - `KBMemoryStore.deleteRecord(id, {rebuildGraph})` now returns `bool`,
    writes a tombstone into the `DELETIONS.md` ledger, bumps the MEMORY.md
    revision generation, and (by default) regenerates `GRAPH.md`.
  - New `KBMemoryStore.deleteRecordByText(text, {type, rebuildGraph})` deletes
    records by exact normalized text (optionally restricted to
    `question`/`answer`/`note`).
  - New `KBMemoryStore.isDeleted(id)` / `hasDeletedText(text)` ledger queries.
  - Capture-time tombstone guard (`respectTombstones`, default `true`): text
    deleted by one agent process is not re-captured by another.
  - `MemoryDeletionService` is public (ledger access,
    `pendingDeletions()`, `markConsolidated(seq)`); `consolidate()` now feeds
    deletion cleanup notices to the consolidation agent and skips them on the
    next run, so deleted records are not resurrected in MEMORY.md.
  - `MemoryRevisionService` mixes a generation counter (`MEMORY.revision`)
    into revision hashes: a consolidation running while a record is deleted
    fails its conditional write (`ConcurrentRevisionException`) instead of
    writing stale content.
  - Fixed `buildEntityTags` dropping system tags (`#note`, `#source_*`) when
    a note was re-rendered (relations, promote, access tracking).
- **Memory overview public data API** (`lib/src/overview/memory_overview.dart`).
  - `MemoryOverviewService.build({types, area, author, tags, limit})` builds a
    serializable snapshot: record list (`MemoryOverviewEntry`) plus a typed
    graph (`MemoryGraphNode`, `MemoryGraphEdge`, `MemoryOverviewGraph`) with
    scope/timestamp metadata; `toJson()`/`fromJson()` for transport.
  - `KBMemoryStore.overview({...})` convenience method.
  - Edge types: persisted relations (`supports`, `contradicts`, ...),
    `answers` (question↔answer/note), wiki-link `links_to`. Dangling edges are
    dropped so clients receive a self-contained graph.
- **Search hang fix.** `KBSearchEngine.searchByText` LLM stages (tag
  generation, reranking) are now bounded by `llmTimeout` (default 30s,
  constructor and per-call override). On timeout the search degrades
  gracefully to keyword-only matching / pre-rerank ranking and reports it in
  `KBTextSearchResult.warnings`.
- CLI: `agent_memory memory delete` supports `--text` (exact-text deletion,
  `--type` filter) in addition to `--id`; `--no-graph` skips graph rebuild.
- Refactors: `MemoryRecord`, `KBMemoryEnrichment` extracted from
  `kb_memory_store.dart` (public API unchanged).

## 0.0.6

- Web fix: `sqlite_kb_storage` (dart:ffi) is no longer re-exported from the
  package barrels — importing `flutter_agent_memory` compiles for web again.
  SQLite hosts import `src/storage/sqlite_kb_storage.dart` directly.

## 0.0.5

- `KBSearchEngine.searchByKeywords`: public keyword-only search that works
  without an LLM provider (used as the no-provider fallback by hosts).
- Keyword tokenization now keeps Cyrillic (`\u0400-\u04FF`) words.

## 0.0.3

- Published to pub.dev.
- Switched `fa_llm` dependency from git to hosted (`^0.1.0`).

## 0.0.2

- Adjusted dependencies for hosted publishing.
- Updated CI workflows.

## 0.0.1

- Initial release of `agent_memory`.
- CLI with commands: `process`, `regenerate`, `stats`, `search-tags`, `search`, `memory`, `skill`.
- LLM providers: OpenAI, OpenRouter, Ollama (OpenAI-compatible).
- Markdown knowledge base generation (questions, answers, notes, people, topics, areas, stats).
- Agent memory CRUD: add, ask, list, delete, rank, update.
- Memory levels for notes: `raw`, `consolidated`, `concept`.
- Typed relations between notes (`supports`, `contradicts`, `part_of`, etc.) and an Obsidian-compatible knowledge graph (`GRAPH.md` with Mermaid diagram).
- CLI memory subcommands: `relate`, `promote`, `graph`.
- Natural-language search with AI-generated tags.
- Cross-platform install scripts and native binary compilation.
- GitHub Actions workflows for CI, release, and pub.dev publishing.
- Pre-commit hooks with `dart analyze`, tests, coverage ratchet, and duplication gate.
