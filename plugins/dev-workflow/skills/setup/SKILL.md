---
name: setup
description: Use when initializing dev-workflow in a project for the first time, or when the user asks to bootstrap/configure the dev workflow.
disable-model-invocation: true
argument-hint: (no arguments)
---

# Dev Workflow Setup

Bootstrap the current project for the dev-workflow plugin. Run each step, skipping anything that already exists.

## Steps

1. **Create the memory and state structure** (skip anything that already exists):
   - `.claude/memory/research/.gitkeep`, `.claude/memory/lessons/.gitkeep`
   - `.claude/memory/decisions.md` — seed with `# Architecture Decisions`
   - `.claude/memory/INDEX.md` — generate it: `plugins/dev-workflow/scripts/memory-index.sh`
   - `.claude/state/progress/`, `.claude/state/sessions/` — the guard also writes
     `.claude/state/lesson-stats.json` (lesson counters) there on its own; nothing to create.
   - **Migrate** an existing `.claude/PROGRESS.md`: move it to
     `.claude/state/progress/<current-branch-slug>.md`.
   - Add `.claude/state/` to `.gitignore` — work state is local and per-branch;
     `.claude/memory/` stays committed, lessons included.

2. **Disable Claude attribution globally.** Read `~/.claude/settings.json`; if the `attribution` key is missing, ask the user for permission, then merge in:
   ```json
   { "attribution": { "commit": "", "pr": "" } }
   ```
   Do not clobber other keys.

3. **Check GitHub CLI**: run `gh auth status`. If not authenticated, tell the user to run `! gh auth login` (needed for the draft-PR workflow).

4. **Ask the user only about `.claude/memory/`**: research, decisions and lessons are committed by default (a lesson the team cannot see is a lesson relearned) — ask whether this project prefers them gitignored instead. `.claude/state/` is always local; it is not a question.

5. **Report** what was created, what was skipped, and any missing prerequisites.
