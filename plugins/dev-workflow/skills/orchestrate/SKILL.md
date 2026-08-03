---
name: orchestrate
description: Use when a task involves substantial codebase exploration, documentation research, or a well-scoped implementation chunk - anything whose raw output would flood the main context.
---

# Orchestrate

The main session is the conductor: it decomposes, delegates, synthesizes, and decides. Bulky work runs in subagents so their tool output never enters the main context — only conclusions come back.

## Delegation table

| Task | Delegate to | Minimum brief |
|---|---|---|
| Codebase exploration, "where/how is X done" | `researcher` | precise question, where to look, expected answer shape |
| Library/API/doc/web research | `researcher` | precise question, library + version, expected answer shape |
| Implementing a well-specified task | `coder` | full brief (see below) |
| Reviewing a diff before PR ready | `reviewer` | exact base ref, intent of the change |
| Browser/E2E tests (Playwright) for UI flows | `browser-tester` | app start command/URL, flows to cover, edge cases, whether it may install Playwright |
| Quick single-fact lookup (known file/symbol) | do it directly | — |
| Decisions, synthesis, user dialogue | never delegate | — |

## Subagents start blank

A subagent sees **none** of this conversation: not the files you've read, not the user's phrasing, not other agents' results. Everything it needs must be in the brief — absolute paths, exact git refs, decisions already made, constraints already agreed with the user. If a second agent needs a first agent's findings, paste the relevant conclusions into its brief yourself.

## Briefs

**`researcher`** — the precise question; where to look (paths, or library + version for doc research); the shape of the answer you need (a file list? a yes/no with evidence? an API signature?).

**`coder`** — must contain, explicitly:
1. **Goal** — what and why, acceptance criteria
2. **Files** — where to work, relevant existing utilities/patterns to reuse
3. **Constraints** — style, APIs to use/avoid, what NOT to touch
4. **Verification** — exact commands to run (tests, build, lint)

If you can't write that brief yet, send the `researcher` first — an under-specified coder wastes an expensive model.

**`reviewer`** — the exact diff range (`git diff <base>...HEAD` with a real base ref, not "the recent changes") and one sentence on what the change is supposed to do, so it can judge intent vs. implementation.

**`browser-tester`** — how to start the app (command and URL), the list of flows to cover, the failure/edge cases that matter, and whether it may install Playwright if missing (otherwise it stops and reports). Without a flow list it will guess.

Delegating exploration to the `researcher` is also the cheap path: it runs on a cost-efficient model, while `coder`/`reviewer` run on an expensive one — burn researcher tokens to save coder tokens.

## Feedback loop

- `reviewer` returns **needs work** → send the findings back to the `coder` as a new brief. Don't fix the code yourself in the main context.
- `coder` reports "task bigger than specified" → re-scope: split the task, possibly send a `researcher` first, then re-brief.
- **Spot-check the coder's claims**: re-run the single verification command it reported (the test/build command from its brief). One command, not a re-review — the full review is the `reviewer`'s job.

## Parallelism

- Independent read-only subtasks (researchers, reviewers) → launch **in parallel** (one message, multiple calls).
- **Never run two `coder` agents whose file sets may overlap** — concurrent edits corrupt each other. Serialize, or split by directory with explicit "do NOT touch" constraints.
- Keep fan-out modest (~3-4 agents); beyond that, synthesis quality drops.

## Rules

- Don't redo delegated work yourself; wait for the result.
- Findings worth keeping → save via the `project-memory` skill.
- Branch, commits, and PR belong to the orchestrator via the `feature-workflow` skill; the `coder` commits only if its brief explicitly says so.
- After a significant delegated chunk lands → update PROGRESS.md via the `session-handoff` skill.
- Relay agent conclusions to the user in your own words; their final message isn't shown to the user.
