#!/usr/bin/env bash
# Tests for session-context.sh: registry, collisions, staleness, injection.
set -u

SCRIPTS="$(cd "$(dirname "$0")/../scripts" && pwd)"
. "$(dirname "$0")/lib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

bash -n "$SCRIPTS/session-context.sh" || fail=1

REPO="$WORK/repo"
make_repo "$REPO" feat/alpha

run_start() { # session_id -> stdout of the hook
  printf '{"session_id":"%s","cwd":"%s","source":"startup","hook_event_name":"SessionStart"}' "$1" "$REPO" \
    | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/session-context.sh" 2>/dev/null
}

# --- registration ---
out=$(run_start sess-one)
check registry-written 1 "$(ls "$REPO/.claude/state/sessions" | wc -l | tr -d ' ')"
check_contains registry-branch '"branch": "feat/alpha"' "$(cat "$REPO/.claude/state/sessions/sess-one.json")"
check_contains policy-injected "Standing policy" "$out"

# --- no collision banner when alone ---
check_lacks alone-no-collision "another session" "$out"

# --- collision on the SAME branch ---
now=$(date +%s)
printf '{"session_id":"other","pid":%s,"branch":"feat/alpha","cwd":"%s","started_at":"x","started_at_epoch":%s,"last_seen":"x","last_seen_epoch":%s}\n' \
  "$$" "$REPO" "$now" "$now" > "$REPO/.claude/state/sessions/other.json"
out=$(run_start sess-two)
check_contains collision-same-branch "feat/alpha" "$out"
check_contains collision-warned "another session" "$out"

# --- a session on a DIFFERENT branch is informational, not a warning ---
rm -f "$REPO/.claude/state/sessions/other.json"
printf '{"session_id":"elsewhere","pid":%s,"branch":"feat/beta","cwd":"%s","started_at":"x","started_at_epoch":%s,"last_seen":"x","last_seen_epoch":%s}\n' \
  "$$" "$REPO" "$now" "$now" > "$REPO/.claude/state/sessions/elsewhere.json"
out=$(run_start sess-three)
check_contains other-branch-listed "feat/beta" "$out"
check_lacks other-branch-not-warned "may be overwritten" "$out"

# --- dead sessions are purged ---
printf '{"session_id":"ghost","pid":4194303,"branch":"feat/alpha","cwd":"%s","started_at":"x","started_at_epoch":%s,"last_seen":"x","last_seen_epoch":%s}\n' \
  "$REPO" "$now" "$now" > "$REPO/.claude/state/sessions/ghost.json"
run_start sess-four >/dev/null
[ -f "$REPO/.claude/state/sessions/ghost.json" ] && { echo "FAIL ghost-purged"; fail=1; } || echo "PASS ghost-purged"

# --- progress file of the CURRENT branch is injected, others are not ---
mkdir -p "$REPO/.claude/state/progress"
printf '# Progress\n**Updated:** 2020-01-01 00:00\n**Branch:** feat/alpha\n\nALPHA-MARKER\n' \
  > "$REPO/.claude/state/progress/feat-alpha.md"
printf '# Progress\nBETA-MARKER\n' > "$REPO/.claude/state/progress/feat-beta.md"
out=$(run_start sess-five)
check_contains progress-current "ALPHA-MARKER" "$out"
check_lacks progress-other "BETA-MARKER" "$out"

# --- staleness: a commit made after "Updated:" raises the banner ---
echo change > "$REPO/later.txt"
git -C "$REPO" add later.txt
git -C "$REPO" commit -q -m "chore: later"
out=$(run_start sess-six)
check_contains stale-banner "may be out of date" "$out"

# --- fresh progress (updated after the last commit) raises nothing ---
printf '# Progress\n**Updated:** 2099-01-01 00:00\n**Branch:** feat/alpha\n\nALPHA-MARKER\n' \
  > "$REPO/.claude/state/progress/feat-alpha.md"
out=$(run_start sess-seven)
check_lacks fresh-no-banner "may be out of date" "$out"

# --- legacy .claude/PROGRESS.md is still read, with a migration notice ---
LEG="$WORK/legacy"
make_repo "$LEG" main
mkdir -p "$LEG/.claude"
printf '# Progress\nLEGACY-MARKER\n' > "$LEG/.claude/PROGRESS.md"
out=$(printf '{"session_id":"leg","cwd":"%s","source":"startup"}' "$LEG" \
  | CLAUDE_PROJECT_DIR="$LEG" bash "$SCRIPTS/session-context.sh" 2>/dev/null)
check_contains legacy-read "LEGACY-MARKER" "$out"
check_contains legacy-notice "/dev-workflow:setup" "$out"

# --- never fails, even outside a git repo with no .claude at all ---
mkdir -p "$WORK/bare"
printf '{"session_id":"bare","cwd":"%s","source":"startup"}' "$WORK/bare" \
  | CLAUDE_PROJECT_DIR="$WORK/bare" bash "$SCRIPTS/session-context.sh" >/dev/null 2>&1
check bare-exit-zero 0 "$?"

# --- malformed stdin must not crash the hook ---
printf 'not json' | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/session-context.sh" >/dev/null 2>&1
check malformed-exit-zero 0 "$?"

report session
