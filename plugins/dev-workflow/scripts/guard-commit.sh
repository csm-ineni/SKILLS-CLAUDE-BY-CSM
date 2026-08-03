#!/usr/bin/env bash
# PreToolUse guard (matcher: Bash): block git commit / gh pr commands whose
# text credits Claude (Co-Authored-By trailer, "Generated with Claude Code",
# anthropic noreply address). Exit 2 blocks the tool call; anything else allows it.
set -uo pipefail

input=$(cat)

extract_cmd() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$input" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("command", ""))
except Exception:
    pass
' 2>/dev/null
  elif command -v python >/dev/null 2>&1; then
    printf '%s' "$input" | python -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("command", ""))
except Exception:
    pass
' 2>/dev/null
  else
    return 1
  fi
}

cmd=$(extract_cmd) || {
  # exit 1 (non-blocking error) so the warning is surfaced instead of silently allowing.
  echo "dev-workflow: guard-commit.sh needs jq or python to parse hook input; attribution guard skipped." >&2
  exit 1
}
[ -n "$cmd" ] || exit 0

case "$cmd" in
  *"git commit"* | *"gh pr create"* | *"gh pr edit"* | *"git merge"* | *"git tag"*) ;;
  *) exit 0 ;;
esac

ATTRIB_RE='co-authored-by|generated with .{0,10}claude|noreply@anthropic\.com'

if printf '%s' "$cmd" | grep -qiE "$ATTRIB_RE"; then
  echo "dev-workflow: blocked — commit/PR text must not contain Claude attribution (Co-Authored-By, 'Generated with Claude Code', noreply@anthropic.com). Rewrite the message without it." >&2
  exit 2
fi

# Message supplied via a file (-F/--file/--body-file): scan that file too.
# Handles separated (-F path, --file path), = (--file=path) and attached (-Fpath)
# forms, and quoted paths containing spaces.
scan_msg_file() {
  f=$1
  # Relative paths resolve against the hook's cwd, not any `cd` inside the
  # command — also try the project root as a best effort.
  for candidate in "$f" "${CLAUDE_PROJECT_DIR:-.}/$f"; do
    if [ -f "$candidate" ] && grep -qiE "$ATTRIB_RE" "$candidate"; then
      echo "dev-workflow: blocked — the message file '$candidate' contains Claude attribution (Co-Authored-By, 'Generated with Claude Code', noreply@anthropic.com). Remove it before committing." >&2
      exit 2
    fi
  done
}

printf '%s' "$cmd" \
  | grep -oE -- '(-F|--file|--body-file)=?[ ]*("[^"]+"|'\''[^'\'']+'\''|[^ ;|&]+)' 2>/dev/null \
  | sed -E 's/^(-F|--file|--body-file)=?[ ]*//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/' \
  | while IFS= read -r f; do
      [ -n "$f" ] && scan_msg_file "$f"
    done
# The while loop runs in a subshell; propagate a block verdict.
rc=$?
[ "$rc" -eq 2 ] && exit 2

exit 0
