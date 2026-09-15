#!/usr/bin/env bash
# UserPromptSubmit hook: attach a one-line standing reminder so the workflow
# keeps being applied in long sessions. Throttled: emitted at most once every
# 30 minutes per project, to avoid taxing every prompt and dulling the reminder
# through repetition. The PreCompact hook clears the stamp so the reminder
# re-fires on the first prompt after compaction.
# The stamp lives in the user's cache dir (never in the project working tree),
# keyed by a hash of the project path and the current branch, so neither two
# projects nor two branches throttle each other.
set -u

THROTTLE_SECONDS=1800

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

input=$(cat 2>/dev/null || true)
project="${CLAUDE_PROJECT_DIR:-$PWD}"
slug=$(dw_branch_slug "$project")

# Heartbeat: keep this session's registry entry fresh so other sessions can see it.
# The id comes from stdin: it is a path component here, so it goes through the
# same guard as the two session hooks before anything is built from it.
session_id=$(dw_json_get "$input" session_id 2>/dev/null)
if dw_safe_id "$session_id"; then
  entry="$(dw_sessions_dir "$project")/$session_id.json"
  if [ -f "$entry" ]; then
    now_iso=$(dw_now_iso); now_epoch=$(dw_now_epoch)
    sed -e "s/\"last_seen\": \"[^\"]*\"/\"last_seen\": \"$now_iso\"/" \
        -e "s/\"last_seen_epoch\": [0-9]*/\"last_seen_epoch\": $now_epoch/" \
        "$entry" 2>/dev/null | dw_atomic_write "$entry" 2>/dev/null || true
  fi
fi

# Throttle is keyed per project AND branch, so two branches don't silence each other.
key=$(printf '%s@%s' "$project" "$slug" | cksum | cut -d' ' -f1)
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
