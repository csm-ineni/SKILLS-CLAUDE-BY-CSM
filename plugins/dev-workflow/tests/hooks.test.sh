#!/usr/bin/env bash
# Golden-input tests for the plugin's hook scripts.
# Run: bash plugins/dev-workflow/tests/hooks.test.sh
# The attribution string is assembled dynamically so the plugin's own
# PreToolUse guard doesn't block the command that launches this file.
set -u

SCRIPTS="$(cd "$(dirname "$0")/../scripts" && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

. "$(dirname "$0")/lib.sh"

ATTRIB="Co-Authored"-"By: Claude <noreply@"anthropic".com>"

guard() { # json -> exit code
  printf '%s' "$1" | bash "$SCRIPTS/guard-commit.sh" >/dev/null 2>&1
  echo $?
}

bash -n "$SCRIPTS/guard-commit.sh" || fail=1
bash -n "$SCRIPTS/prompt-reminder.sh" || fail=1
bash -n "$SCRIPTS/precompact-reminder.sh" || fail=1

# --- guard-commit.sh ---
check inline-attribution 2 "$(guard "{\"tool_input\":{\"command\":\"git commit -m \\\"x $ATTRIB\\\"\"}}")"
check clean-commit       0 "$(guard '{"tool_input":{"command":"git commit -m \"feat: clean\""}}')"
check non-commit         0 "$(guard '{"tool_input":{"command":"ls -la"}}')"
check malformed-json     0 "$(guard 'not json at all')"

msg="$WORK/msg.txt"; printf 'feat: x\n\n%s\n' "$ATTRIB" > "$msg"
check file-sep           2 "$(guard "{\"tool_input\":{\"command\":\"git commit -F $msg\"}}")"
check file-equals        2 "$(guard "{\"tool_input\":{\"command\":\"git commit --file=$msg\"}}")"
check file-attached      2 "$(guard "{\"tool_input\":{\"command\":\"git commit -F$msg\"}}")"
check body-file          2 "$(guard "{\"tool_input\":{\"command\":\"gh pr create --body-file $msg\"}}")"

spaced="$WORK/my msg.txt"; printf '%s\n' "$ATTRIB" > "$spaced"
check file-quoted-space  2 "$(guard "{\"tool_input\":{\"command\":\"git commit -F \\\"$spaced\\\"\"}}")"

rel_dir="$WORK/proj"; mkdir -p "$rel_dir"; printf '%s\n' "$ATTRIB" > "$rel_dir/m.txt"
check file-relative      2 "$(printf '%s' "{\"tool_input\":{\"command\":\"git commit -F m.txt\"}}" | CLAUDE_PROJECT_DIR="$rel_dir" bash "$SCRIPTS/guard-commit.sh" >/dev/null 2>&1; echo $?)"

printf 'feat: clean body\n' > "$msg"
check file-clean         0 "$(guard "{\"tool_input\":{\"command\":\"git commit -F $msg\"}}")"

# --- prompt-reminder.sh throttle (isolated cache + project) ---
export XDG_CACHE_HOME="$WORK/cache" CLAUDE_PROJECT_DIR="$WORK/projA"
mkdir -p "$CLAUDE_PROJECT_DIR"
out1=$(bash "$SCRIPTS/prompt-reminder.sh"); out2=$(bash "$SCRIPTS/prompt-reminder.sh")
[ -n "$out1" ] && echo "PASS reminder-first-emits"     || { echo "FAIL reminder-first-emits"; fail=1; }
[ -z "$out2" ] && echo "PASS reminder-second-throttled" || { echo "FAIL reminder-second-throttled"; fail=1; }

# no stamp in the project tree
if [ -e "$CLAUDE_PROJECT_DIR/.claude/.dev-workflow-reminder-stamp" ]; then
  echo "FAIL stamp-outside-project"; fail=1
else
  echo "PASS stamp-outside-project"
fi

# another project is not throttled by projA's stamp
out3=$(CLAUDE_PROJECT_DIR="$WORK/projB" bash "$SCRIPTS/prompt-reminder.sh")
[ -n "$out3" ] && echo "PASS reminder-per-project" || { echo "FAIL reminder-per-project"; fail=1; }

# precompact clears the stamp -> reminder re-fires
bash "$SCRIPTS/precompact-reminder.sh" >/dev/null
out4=$(bash "$SCRIPTS/prompt-reminder.sh")
[ -n "$out4" ] && echo "PASS reminder-after-compaction" || { echo "FAIL reminder-after-compaction"; fail=1; }

report hooks
