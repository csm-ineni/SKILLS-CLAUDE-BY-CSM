---
name: project-memory
description: Use before researching a library, API, framework, error message, or codebase question, and after completing any significant research or web/doc lookup. Prevents duplicate research across sessions.
---

# Project Memory

Persistent research cache in `.claude/memory/`. The same question must never be researched twice.

## Three memories, three purposes

| Directory | Holds | Written by |
|---|---|---|
| `research/` | Facts: library behaviour, API shapes, how this codebase does X | after any non-trivial lookup |
| `decisions.md` | Architectural choices and their rationale | when a choice is made |
| `lessons/` | Mistakes already paid for, with a trigger that can warn or block | `dev-workflow:learn` |

`INDEX.md` is **generated** — run `plugins/dev-workflow/scripts/memory-index.sh` after adding an
entry, and never edit it by hand. Hand-editing is how a concurrent session's entry gets lost.

## Before any research

1. Read `.claude/memory/INDEX.md` (if missing, run `/dev-workflow:setup` first or proceed without memory).
2. If an entry covers the question: read it, check the date and whether it still matches reality (versions, files it references). Reuse it; only re-research the delta.
3. If no entry covers it: research, then save (below). Prefer delegating the research itself to the `researcher` agent to keep this context lean.

## After significant research

Save `.claude/memory/research/<kebab-topic>.md`, frontmatter first — the index generator reads
`topic`, `answer` and `date` from it, and falls back to the first heading and the first prose line
when they are missing:

```markdown
---
topic: Prisma migrate on a shared dev database
answer: Always --create-only, review the SQL, then apply
date: 2026-03-12
---

# <Topic>
**Question:** <what was asked>
**Answer:** <condensed conclusion, decision-ready>
**Sources:** <URLs, file:line refs>
```

Then run `plugins/dev-workflow/scripts/memory-index.sh`; it rewrites `INDEX.md` from those keys.

"Significant" = took more than a couple of tool calls, or would cost real time to redo: library evaluations, API behaviors, gotchas, architecture explorations, debugging root causes.

## Maintenance

- An entry contradicted by reality is worse than no entry: fix or delete it immediately, then regenerate the index.
- Architecture choices go to `.claude/memory/decisions.md` (decision, why, date) — not to research files.
- Keep entries condensed. This is a cache of conclusions, not a scrapbook of raw output.
