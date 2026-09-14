#!/usr/bin/env bash
# Tests for scripts/lib/state.sh
set -u

SCRIPTS="$(cd "$(dirname "$0")/../scripts" && pwd)"
. "$(dirname "$0")/lib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

bash -n "$SCRIPTS/lib/state.sh" || fail=1
. "$SCRIPTS/lib/state.sh"

# --- dw_json_get ---
json='{"session_id":"abc-123","cwd":"/tmp/x","tool_input":{"command":"git status"}}'
check json-scalar   "abc-123"    "$(dw_json_get "$json" session_id)"
check json-nested   "git status" "$(dw_json_get "$json" tool_input.command)"
check json-missing  ""           "$(dw_json_get "$json" nope.nothing)"
check json-garbage  ""           "$(dw_json_get 'not json' session_id)"

# --- dw_branch_slug ---
make_repo "$WORK/plain" main
check slug-plain "main" "$(dw_branch_slug "$WORK/plain")"

make_repo "$WORK/slashes" feat/my-thing
check slug-slash "feat-my-thing" "$(dw_branch_slug "$WORK/slashes")"

# Spaces are illegal in git ref names, so the exotic case uses accents and @.
make_repo "$WORK/exotic" "feat/Ét@rangé_x"
check slug-exotic "feat-t-rang-_x" "$(dw_branch_slug "$WORK/exotic")"

sha=$(git -C "$WORK/plain" rev-parse --short=7 HEAD)
git -C "$WORK/plain" checkout -q --detach HEAD
check slug-detached "detached-$sha" "$(dw_branch_slug "$WORK/plain")"

mkdir -p "$WORK/nogit"
check slug-nogit "no-branch" "$(dw_branch_slug "$WORK/nogit")"

# --- paths ---
check path-progress "$WORK/plain/.claude/state/progress/detached-$sha.md" "$(dw_progress_file "$WORK/plain")"
check path-sessions "$WORK/nogit/.claude/state/sessions" "$(dw_sessions_dir "$WORK/nogit")"
check path-lessons  "$WORK/nogit/.claude/memory/lessons" "$(dw_lessons_dir "$WORK/nogit")"

# --- dw_atomic_write ---
dest="$WORK/deep/nested/out.txt"
printf 'hello\n' | dw_atomic_write "$dest"
check atomic-content "hello" "$(cat "$dest")"
check atomic-no-temp "0" "$(find "$WORK/deep/nested" -name '.dw.*' | wc -l | tr -d ' ')"

# --- timestamps ---
case "$(dw_now_iso)" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) echo "PASS iso-shape" ;;
  *) echo "FAIL iso-shape got=$(dw_now_iso)"; fail=1 ;;
esac
case "$(dw_now_epoch)" in
  ''|*[!0-9]*) echo "FAIL epoch-numeric"; fail=1 ;;
  *) echo "PASS epoch-numeric" ;;
esac

# --- dw_session_alive ---
sess="$WORK/sessions"; mkdir -p "$sess"
now=$(dw_now_epoch)
printf '{"session_id":"live","pid":%s,"branch":"main","cwd":"/tmp","started_at_epoch":%s,"last_seen_epoch":%s}\n' \
  "$$" "$now" "$now" > "$sess/live.json"
dw_session_alive "$sess/live.json" && echo "PASS alive-self" || { echo "FAIL alive-self"; fail=1; }

# A pid that cannot exist.
printf '{"session_id":"dead","pid":4194303,"branch":"main","cwd":"/tmp","started_at_epoch":%s,"last_seen_epoch":%s}\n' \
  "$now" "$now" > "$sess/dead.json"
dw_session_alive "$sess/dead.json" && { echo "FAIL alive-dead-pid"; fail=1; } || echo "PASS alive-dead-pid"

# Live pid, but untouched for more than 24h -> stale (pid reuse guard).
old=$((now - 90000))
printf '{"session_id":"old","pid":%s,"branch":"main","cwd":"/tmp","started_at_epoch":%s,"last_seen_epoch":%s}\n' \
  "$$" "$old" "$old" > "$sess/old.json"
dw_session_alive "$sess/old.json" && { echo "FAIL alive-ttl"; fail=1; } || echo "PASS alive-ttl"

# Live pid, idle for 3h -> still alive (the pid is what matters).
idle=$((now - 10800))
printf '{"session_id":"idle","pid":%s,"branch":"main","cwd":"/tmp","started_at_epoch":%s,"last_seen_epoch":%s}\n' \
  "$$" "$idle" "$idle" > "$sess/idle.json"
dw_session_alive "$sess/idle.json" && echo "PASS alive-idle" || { echo "FAIL alive-idle"; fail=1; }

check_lacks malformed-quiet "Traceback" "$(printf 'garbage' > "$sess/bad.json"; dw_session_alive "$sess/bad.json" 2>&1)"

report state
