#!/usr/bin/env bash
# PreToolUse guard (matcher: Bash): block git commit / gh pr commands whose
# text credits Claude (Co-Authored-By trailer, "Generated with Claude Code",
# anthropic noreply address). Exit 2 blocks the tool call; anything else allows it.
set -uo pipefail

input=$(cat)

cmd=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("command", ""))
except Exception:
    pass
' 2>/dev/null) || exit 0

case "$cmd" in
  *"git commit"* | *"gh pr create"* | *"gh pr edit"* | *"git merge"* | *"git tag"*) ;;
  *) exit 0 ;;
esac

if printf '%s' "$cmd" | grep -qiE 'co-authored-by|generated with .{0,10}claude|noreply@anthropic\.com'; then
  echo "dev-workflow: blocked — commit/PR text must not contain Claude attribution (Co-Authored-By, 'Generated with Claude Code', noreply@anthropic.com). Rewrite the message without it." >&2
  exit 2
fi
exit 0
