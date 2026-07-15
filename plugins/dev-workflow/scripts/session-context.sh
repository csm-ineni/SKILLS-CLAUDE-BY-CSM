#!/usr/bin/env bash
# SessionStart hook: inject the project's progress file and memory index into
# context so a new session resumes where the previous one stopped.
set -uo pipefail

dir="${CLAUDE_PROJECT_DIR:-$PWD}"
progress="$dir/.claude/PROGRESS.md"
index="$dir/.claude/memory/INDEX.md"

[ -f "$progress" ] || [ -f "$index" ] || exit 0

echo "<dev-workflow-context>"
if [ -f "$progress" ]; then
  echo "== Session progress (.claude/PROGRESS.md) — resume from here instead of re-exploring =="
  cat "$progress"
  echo ""
fi
if [ -f "$index" ]; then
  echo "== Project memory index (.claude/memory/INDEX.md) — check for an existing entry before any new research =="
  cat "$index"
fi
echo "</dev-workflow-context>"
exit 0
