#!/usr/bin/env bash
# UserPromptSubmit hook: attach a one-line standing reminder so the workflow
# keeps being applied in long sessions. Throttled: emitted at most once every
# 30 minutes per project, to avoid taxing every prompt and dulling the reminder
# through repetition. The PreCompact hook clears the stamp so the reminder
# re-fires on the first prompt after compaction.
# The stamp lives in the user's cache dir (never in the project working tree),
# keyed by a hash of the project path so projects don't throttle each other.
set -u

THROTTLE_SECONDS=1800
project="${CLAUDE_PROJECT_DIR:-$PWD}"
key=$(printf '%s' "$project" | cksum | cut -d' ' -f1)
stamp_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-dev-workflow"
stamp_file="$stamp_dir/reminder-$key"

now=$(date +%s)
if [ -f "$stamp_file" ]; then
  last=$(cat "$stamp_file" 2>/dev/null || echo 0)
  case "$last" in (*[!0-9]*|'') last=0 ;; esac
  if [ $((now - last)) -lt "$THROTTLE_SECONDS" ]; then
    exit 0
  fi
fi

mkdir -p "$stamp_dir" 2>/dev/null || true
printf '%s' "$now" > "$stamp_file" 2>/dev/null || true

echo "dev-workflow: apply plugin skills without being asked — project-memory before any research, coding-rules when coding, feature-workflow for branches/commits/PRs (no AI attribution), orchestrate+subagents for bulky work, session-handoff at milestones."
exit 0
