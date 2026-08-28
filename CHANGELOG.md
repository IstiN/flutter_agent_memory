# Changelog

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
