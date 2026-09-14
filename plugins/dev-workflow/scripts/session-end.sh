#!/usr/bin/env bash
# SessionEnd hook: drop this session's registry entry so parallel-session
# warnings stay accurate. Optimistic by design -- the doc does not guarantee
# this hook runs when the process is killed, so SessionStart's pid-based purge
# remains the real guarantee.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

input=$(cat 2>/dev/null || true)
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
session_id=$(dw_json_get "$input" session_id 2>/dev/null)

[ -n "$session_id" ] || exit 0
case "$session_id" in */*|..|.) exit 0 ;; esac   # never let an id escape the directory

rm -f "$(dw_sessions_dir "$dir")/$session_id.json" 2>/dev/null || true
exit 0
