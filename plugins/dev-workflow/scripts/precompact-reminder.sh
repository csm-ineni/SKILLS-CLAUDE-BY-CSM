#!/usr/bin/env bash
# PreCompact hook: remind the agent to persist progress before context compaction,
# and clear the prompt-reminder throttle stamp so the standing-policy reminder
# re-fires on the first prompt after compaction (compaction wipes it from context).
set -u

project="${CLAUDE_PROJECT_DIR:-$PWD}"
key=$(printf '%s' "$project" | cksum | cut -d' ' -f1)
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/claude-dev-workflow/reminder-$key" 2>/dev/null || true

echo "dev-workflow: context is about to be compacted. If .claude/PROGRESS.md is stale, update it NOW (current task, done, next concrete step, open questions, active branch) so nothing is lost."
exit 0
