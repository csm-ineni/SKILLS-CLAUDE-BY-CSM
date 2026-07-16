---
name: orchestrate
description: Use when a task involves substantial codebase exploration, documentation research, or a well-scoped implementation chunk - anything whose raw output would flood the main context.
---

# Orchestrate

The main session is the conductor: it decomposes, delegates, synthesizes, and decides. Bulky work runs in subagents so their tool output never enters the main context — only conclusions come back.

## Delegation table

| Task | Delegate to | Model |
|---|---|---|
| Codebase exploration, "where/how is X done" | `researcher` | haiku (cheap) |
| Library/API/doc/web research | `researcher` | haiku |
| Implementing a well-specified task | `coder` | opus |
| Reviewing a diff before PR ready | `reviewer` | opus |
| Browser/E2E tests (Playwright) for UI flows | `browser-tester` | sonnet |
| Quick single-fact lookup (known file/symbol) | do it directly | — |
| Decisions, synthesis, user dialogue | never delegate | — |

## Briefing the coder

A `coder` brief must contain, explicitly:
1. **Goal** — what and why, acceptance criteria
2. **Files** — where to work, relevant existing utilities/patterns to reuse
3. **Constraints** — style, APIs to use/avoid, what NOT to touch
4. **Verification** — exact commands to run (tests, build, lint)

If you can't write that brief yet, send the `researcher` first — an under-specified coder wastes an expensive model.

## Rules

- Independent subtasks → launch agents **in parallel** (one message, multiple calls).
- Don't redo delegated work yourself; wait for the result.
- Findings worth keeping → save via the `project-memory` skill.
- Relay agent conclusions to the user in your own words; their final message isn't shown to the user.
