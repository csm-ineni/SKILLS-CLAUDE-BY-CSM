---
name: session-handoff
description: Use when ending a work session, reaching a milestone, before context compaction, or when the user says handoff, pause, stop for today, or resume later. Also use when noticing the branch's progress file is stale after completing a task.
---

# Session Handoff

Persist working state to `.claude/state/progress/<branch-slug>.md` so the next session resumes in seconds instead of re-exploring. The SessionStart hook injects this file automatically at startup.

The file is **per branch** (`<branch-slug>` is the current branch with `/` and exotic characters
turned into `-`), so two sessions on two features no longer overwrite each other. If the
SessionStart banner warned that another live session shares your branch, coordinate before
writing — the registry warns, it does not lock.

## When updating

Overwrite the file (don't append history — git has history) with:

```markdown
# Progress
**Updated:** <YYYY-MM-DD HH:MM>
**Branch:** <active git branch>

## Current task
<one paragraph: what we're building and why>

## Done
- <completed, verified steps only>

## Next step
<the single next concrete action, precise enough to execute blind,
e.g. "implement validateInput() in src/api/handlers.ts per the test in handlers.test.ts">

## Open questions
- <decisions waiting on the user, unresolved unknowns>

## Watch out
- <traps discovered: flaky test X, don't touch Y, config Z is load-bearing>
```

`**Updated:**` is for whoever reads the file — nothing parses it. The SessionStart hook decides
the file is stale by comparing its modification time to the last commit's date, so a file edited
without touching that line is still seen as fresh.

## Rules

- **"Done" means verified.** Never list something as done that wasn't tested/checked.
- **"Next step" is the most valuable line** — write it for someone with zero context.
- Keep the whole file under ~60 lines; link to `.claude/memory/` entries instead of inlining research.
- Update at every milestone, not just at session end — a crash loses everything since the last write.
- **A `Watch out` that outlives the branch is a lesson.** Traps tied to this feature stay here and
  die with the branch; a rule that would have saved you on any branch belongs in
  `.claude/memory/lessons/` — invoke `dev-workflow:learn`.
