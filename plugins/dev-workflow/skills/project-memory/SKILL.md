---
name: project-memory
description: Use before researching a library, API, framework, error message, or codebase question, and after completing any significant research or web/doc lookup. Prevents duplicate research across sessions.
---

# Project Memory

Persistent research cache in `.claude/memory/`. The same question must never be researched twice.

## Before any research

1. Read `.claude/memory/INDEX.md` (if missing, run `/dev-workflow:setup` first or proceed without memory).
2. If an entry covers the question: read it, check the date and whether it still matches reality (versions, files it references). Reuse it; only re-research the delta.
3. If no entry covers it: research, then save (below). Prefer delegating the research itself to the `researcher` agent to keep this context lean.

## After significant research

Save `.claude/memory/research/<kebab-topic>.md`:

```markdown
# <Topic>
**Question:** <what was asked>
**Answer:** <condensed conclusion, decision-ready>
**Sources:** <URLs, file:line refs>
**Date:** <YYYY-MM-DD>
```

Add one line to `INDEX.md`: `- [topic](research/<file>.md) — one-line answer (date)`.

"Significant" = took more than a couple of tool calls, or would cost real time to redo: library evaluations, API behaviors, gotchas, architecture explorations, debugging root causes.

## Maintenance

- An entry contradicted by reality is worse than no entry: fix or delete it immediately, and update its INDEX line.
- Architecture choices go to `.claude/memory/decisions.md` (decision, why, date) — not to research files.
- Keep entries condensed. This is a cache of conclusions, not a scrapbook of raw output.
