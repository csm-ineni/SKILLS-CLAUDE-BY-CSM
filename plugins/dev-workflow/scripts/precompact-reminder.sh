#!/usr/bin/env bash
# PreCompact hook: remind the agent to persist progress before context compaction,
# and clear the prompt-reminder throttle stamp so the standing-policy reminder
# re-fires on the first prompt after compaction (compaction wipes it from context).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

project="${CLAUDE_PROJECT_DIR:-$PWD}"
key=$(printf '%s@%s' "$project" "$(dw_branch_slug "$project")" | cksum | cut -d' ' -f1)
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/claude-dev-workflow/reminder-$key" 2>/dev/null || true

echo "dev-workflow: context is about to be compacted. Update this branch's progress file at $(dw_progress_file "$project") NOW (current task, done, next concrete step, open questions) so nothing is lost. Anything that must survive beyond this branch — a trap, a rule learned the hard way — belongs in a lesson: invoke skill dev-workflow:learn."
exit 0
