#!/usr/bin/env bash
# SessionStart hook: inject the dev-workflow standing policy plus the project's
# progress file and memory index, so every session applies the workflow without
# being reminded and resumes where the previous one stopped.
set -uo pipefail

dir="${CLAUDE_PROJECT_DIR:-$PWD}"
progress="$dir/.claude/PROGRESS.md"
index="$dir/.claude/memory/INDEX.md"

echo "<dev-workflow-context>"
cat <<'POLICY'
== Standing policy (dev-workflow plugin) — apply WITHOUT being asked ==
- Before researching any library/API/error/codebase question: invoke skill dev-workflow:project-memory (reuse .claude/memory/ entries; save findings after).
- When writing or refactoring code: invoke skill dev-workflow:coding-rules first.
- When starting a feature/fix/chore, or committing/pushing/opening a PR: invoke skill dev-workflow:feature-workflow (dedicated branch, Conventional Commits, draft PR, never any Claude/AI attribution).
- For bulky exploration/research or a well-specified implementation chunk: invoke skill dev-workflow:orchestrate and delegate to the researcher (haiku) / coder (opus) / reviewer (opus) / browser-tester (sonnet, Playwright) subagents.
- Before marking a UI-touching PR ready: delegate Playwright browser tests to the browser-tester subagent (sonnet); unit tests alone are not enough for user-facing flows.
- At every milestone, before compaction, and at session end: invoke skill dev-workflow:session-handoff to update .claude/PROGRESS.md.
POLICY

if [ -f "$progress" ]; then
  echo ""
  echo "== Session progress (.claude/PROGRESS.md) — resume from here instead of re-exploring =="
  cat "$progress"
fi
if [ -f "$index" ]; then
  echo ""
  echo "== Project memory index (.claude/memory/INDEX.md) — check for an existing entry before any new research =="
  cat "$index"
fi
if [ ! -f "$progress" ] && [ ! -d "$dir/.claude/memory" ]; then
  echo ""
  echo "== Project not initialized for dev-workflow: suggest running /dev-workflow:setup once (creates .claude/memory/ and PROGRESS.md). =="
fi
echo "</dev-workflow-context>"
exit 0
