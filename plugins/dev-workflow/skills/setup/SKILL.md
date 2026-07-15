---
name: setup
description: Use when initializing dev-workflow in a project for the first time, or when the user asks to bootstrap/configure the dev workflow.
disable-model-invocation: true
argument-hint: (no arguments)
---

# Dev Workflow Setup

Bootstrap the current project for the dev-workflow plugin. Run each step, skipping anything that already exists.

## Steps

1. **Create the memory structure** (skip existing files):
   - `.claude/memory/INDEX.md` — seed with:
     ```markdown
     # Project Memory Index
     One line per entry: - [topic](research/<file>.md) — one-line answer (YYYY-MM-DD)
     ```
   - `.claude/memory/research/` (empty directory, add `.gitkeep`)
   - `.claude/memory/decisions.md` — seed with a `# Architecture Decisions` heading
   - `.claude/PROGRESS.md` — seed with the template from the `session-handoff` skill

2. **Disable Claude attribution globally.** Read `~/.claude/settings.json`; if the `attribution` key is missing, ask the user for permission, then merge in:
   ```json
   { "attribution": { "commit": "", "pr": "" } }
   ```
   Do not clobber other keys.

3. **Check GitHub CLI**: run `gh auth status`. If not authenticated, tell the user to run `! gh auth login` (needed for the draft-PR workflow).

4. **Ask the user** whether `.claude/memory/` and `.claude/PROGRESS.md` should be committed (team-shared) or gitignored (personal). Apply their choice to `.gitignore`.

5. **Report** what was created, what was skipped, and any missing prerequisites.
