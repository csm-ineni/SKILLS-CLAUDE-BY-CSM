---
name: feature-workflow
description: Use when starting work on a new feature, fix, or chore, and whenever committing, pushing, or opening a pull request.
---

# Feature Workflow

Every unit of work lives on a dedicated branch with a draft PR from the first commit. `main`/`master` never receives direct commits.

## Starting work

1. `git fetch` and branch from up-to-date `main`: `git checkout -b <type>/<kebab-slug>`
   - types: `feat/`, `fix/`, `chore/`, `refactor/`, `docs/`, `test/`
2. Implement in small, coherent commits.

## Commits — Conventional Commits, no AI attribution

Format: `<type>(<optional-scope>): <imperative summary ≤72 chars>`, body explaining *why* when non-obvious.

The commit message and PR text contain **only** the change description. They never contain `Co-Authored-By`, "Generated with Claude Code", any Claude/AI mention, or `noreply@anthropic.com`. (A PreToolUse hook blocks violations; the `attribution` setting must also be `""` — see `/dev-workflow:setup`.)

## Draft PR — immediately after the first commit

```bash
git push -u origin <branch>
gh pr create --draft --title "<type>: <summary>" --body "..."
```

PR body structure:

```markdown
## What
<one paragraph>

## Why
<problem or need>

## How to test
<commands or steps>

## Status
- [ ] implementation
- [ ] tests
- [ ] review
```

Keep pushing to the same branch; the draft PR tracks progress.

## Marking ready

Only after: tests pass locally, self-review of the full diff done, and — for non-trivial changes — the `reviewer` agent returned **ready**. Then `gh pr ready`.

## Stacked PRs (PR chains)

When PR B is based on PR A's branch (not on the default branch):

1. Merging PR A does **not** move PR B forward. Before merging B, **retarget** it onto the default branch (`gh pr edit <B> --base develop`) and rebase/merge the updated base into B's branch — otherwise B's code merges into a dead branch and never reaches `develop`/`main`.
2. `MERGED` status ≠ code present in the target branch. After the chain lands, verify **content**, not status: `git log develop --oneline | grep ...` or `git branch --contains <commit> develop` on the actual commits.

## Red flags

- About to commit on `main` → create the branch first, `git stash` if needed
- Branch doing two unrelated things → split into two branches/PRs
- Commit message describing *how* instead of *what/why* → rewrite
