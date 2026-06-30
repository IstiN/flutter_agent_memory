# Changelog

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
