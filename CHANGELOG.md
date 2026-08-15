# Changelog

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
