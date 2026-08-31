# Memory management policies

Canonical, human-readable rules for how agents must manage long-term
memory in `flutter_agent_memory`. These documents are the source of truth;
`lib/src/policy/memory_policy.dart` mirrors them as Dart string constants
(enforced by a sync test), and agent harnesses (e.g. flutter_agent) should
read or link them when building system prompts.

- [memory_add_policy.md](memory_add_policy.md) — what may be stored, the
  supersede rule, scope discipline.
- [tag_taxonomy.md](tag_taxonomy.md) — system tags vs. free tags and their
  conventions.
- [consolidation_rules.md](consolidation_rules.md) — the revision contract,
  tombstone handling, and derivative files.
