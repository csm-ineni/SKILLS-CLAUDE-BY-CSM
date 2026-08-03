#!/usr/bin/env bash
# PreToolUse guard (matcher: Bash): block git commit / gh pr commands whose
# text credits Claude (Co-Authored-By trailer, "Generated with Claude Code",
# anthropic noreply address). Exit 2 blocks the tool call; anything else allows it.
set -uo pipefail

input=$(cat)

extract_cmd() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null
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
    echo "dev-workflow: guard-commit.sh needs jq or python to parse hook input; attribution guard skipped." >&2
    return 1
  fi
}

cmd=$(extract_cmd) || exit 0
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
msg_files=$(printf '%s' "$cmd" | grep -oE '(-F|--file|--body-file)[= ][^ ;|&]+' | sed -E 's/^(-F|--file|--body-file)[= ]//' | tr -d '"'"'" || true)
for f in $msg_files; do
  if [ -f "$f" ] && grep -qiE "$ATTRIB_RE" "$f"; then
    echo "dev-workflow: blocked — the message file '$f' contains Claude attribution (Co-Authored-By, 'Generated with Claude Code', noreply@anthropic.com). Remove it before committing." >&2
    exit 2
  fi
done

exit 0
