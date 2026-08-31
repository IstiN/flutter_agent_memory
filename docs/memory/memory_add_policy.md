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
