#!/usr/bin/env bash
# PreToolUse guard (matcher: Bash|Edit|Write): confront the action against the
# lessons in .claude/memory/lessons/. Level 2 surfaces the lesson and allows;
# level 3 blocks (exit 2) and prints the escape hatch. A broken lesson file must
# never stand between the user and their work: anything unexpected exits 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

input=$(cat 2>/dev/null || true)
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
lessons=$(dw_lessons_dir "$dir")
[ -d "$lessons" ] || exit 0

tool=$(dw_json_get "$input" tool_name 2>/dev/null)
[ -n "$tool" ] || exit 0

case "$tool" in
  Bash)       subject=$(dw_json_get "$input" tool_input.command) ;;
  Edit|Write) subject=$(dw_json_get "$input" tool_input.file_path) ;;
  *)          exit 0 ;;
esac
[ -n "$subject" ] || exit 0

fm() { # <file> <key>
  sed -n '2,/^---$/p' "$1" 2>/dev/null \
    | grep -m1 "^$2:" \
    | sed -E "s/^$2:[[:space:]]*//; s/^\"(.*)\"$/\1/"
}

bump() { # <file> <key>
  f=$1; k=$2
  cur=$(fm "$f" "$k"); case "$cur" in ''|*[!0-9]*) cur=0 ;; esac
  next=$((cur + 1))
  today=$(date -u +%Y-%m-%d)
  sed -e "s/^$k:.*/$k: $next/" -e "s/^last_hit:.*/last_hit: $today/" "$f" 2>/dev/null \
    | dw_atomic_write "$f" 2>/dev/null || true
}

blocked=0
for f in "$lessons"/*.md; do
  [ -f "$f" ] || continue
  rule=$(fm "$f" rule);       [ -n "$rule" ] || continue
  pattern=$(fm "$f" pattern); [ -n "$pattern" ] || continue
  tools=$(fm "$f" tools);     [ -n "$tools" ] || continue

  # Does this lesson cover the current tool?
  printf '%s' "$tools" | tr ',' '\n' | sed 's/[[:space:]]//g' | grep -qx "$tool" || continue

  # An invalid regex must be ignored, never fatal.
  printf '%s' "$subject" | grep -qE "$pattern" 2>/dev/null || continue

  slug=$(basename "$f" .md)
  level=$(fm "$f" level); case "$level" in ''|*[!0-9]*) level=1 ;; esac
  why=$(fm "$f" why)
  # `1,/^---$/d` deletes from line 1 through the closing `---`, i.e. the whole frontmatter.
  body=$(sed -e '1,/^---$/d' "$f" 2>/dev/null | sed '/^$/d' | head -5)

  if [ "$level" -ge 3 ]; then
    # Escape hatch: DW_OVERRIDE=<slug> as a visible prefix in the command.
    if printf '%s' "$subject" | grep -qE "DW_OVERRIDE=$slug([[:space:];&|]|$)"; then
      bump "$f" overrides
      continue
    fi
    echo "dev-workflow: BLOCKED by lesson '$slug'." >&2
    echo "  Rule: $rule" >&2
    [ -n "$why" ] && echo "  Why:  $why" >&2
    [ -n "$body" ] && echo "$body" | sed 's/^/  /' >&2
    echo "  If this is genuinely the right call, rerun with the prefix: DW_OVERRIDE=$slug <your command>" >&2
    bump "$f" hits
    blocked=1
  elif [ "$level" -eq 2 ]; then
    echo "dev-workflow: lesson '$slug' applies here." >&2
    echo "  Rule: $rule" >&2
    [ -n "$why" ] && echo "  Why:  $why" >&2
    [ -n "$body" ] && echo "$body" | sed 's/^/  /' >&2
    bump "$f" hits
  fi
done

[ "$blocked" -eq 1 ] && exit 2
exit 0
