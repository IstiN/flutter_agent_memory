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
