#!/usr/bin/env bash
# SessionStart hook: register this session, warn about parallel sessions on the
# same branch, and inject the standing policy, the branch's progress file, the
# memory index and the active lesson titles.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

input=$(cat 2>/dev/null || true)
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
session_id=$(dw_json_get "$input" session_id 2>/dev/null)
[ -n "$session_id" ] || session_id="unknown-$$"

branch=$(git -C "$dir" branch --show-current 2>/dev/null)
[ -n "$branch" ] || branch="(no branch)"
sessions=$(dw_sessions_dir "$dir")
progress=$(dw_progress_file "$dir")
legacy="$dir/.claude/PROGRESS.md"
index="$dir/.claude/memory/INDEX.md"
lessons=$(dw_lessons_dir "$dir")

mkdir -p "$sessions" 2>/dev/null || true

# Everything this hook prints is injected verbatim into the model's context, and
# the files it reads are committed: a clone or a merge is enough to plant text
# here. Cap what goes in, and make sure nothing can close the wrapping tag.
DW_INJECT_MAX_LINES=200
DW_INJECT_MAX_BYTES=8192
DW_INJECT_MAX_COLS=160
DW_STALE_MARGIN=60        # a commit made right after the write is not staleness

untag() { LC_ALL=C sed -e 's#</*dev-workflow-context>#(dev-workflow tag removed)#g'; }

# Branch names, and the cwd of another session, are as untrusted as file
# contents: a refname may legally contain the closing tag. Everything printed
# below goes through this.
untag_str() { # <value>
  printf '%s' "$1" | untag | LC_ALL=C cut -c1-"$DW_INJECT_MAX_COLS" | tr -d '\n'
}

emit_file() { # <file>
  head -c "$DW_INJECT_MAX_BYTES" "$1" 2>/dev/null | head -n "$DW_INJECT_MAX_LINES" | untag
  emit_bytes=$(wc -c < "$1" 2>/dev/null | tr -d ' ')
  emit_lines=$(wc -l < "$1" 2>/dev/null | tr -d ' ')
  case "$emit_bytes" in ''|*[!0-9]*) emit_bytes=0 ;; esac
  case "$emit_lines" in ''|*[!0-9]*) emit_lines=0 ;; esac
  if [ "$emit_bytes" -gt "$DW_INJECT_MAX_BYTES" ] || [ "$emit_lines" -gt "$DW_INJECT_MAX_LINES" ]; then
    echo "[truncated to $DW_INJECT_MAX_LINES lines / $DW_INJECT_MAX_BYTES bytes — open the file for the rest]"
  fi
}

# --- purge dead sessions, then collect the live ones ---
same_branch=""
other_branches=""
for f in "$sessions"/*.json; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in "$session_id.json") continue ;; esac
  if ! dw_session_alive "$f"; then
    rm -f "$f" 2>/dev/null
    continue
  fi
  j=$(cat "$f" 2>/dev/null)
  b=$(dw_json_get "$j" branch)
  started=$(dw_json_get "$j" started_at_epoch)
  case "$started" in ''|*[!0-9]*) started=$(dw_now_epoch) ;; esac
  age=$(( ($(dw_now_epoch) - started) / 60 ))
  if [ "$b" = "$branch" ]; then
    same_branch="$same_branch$b|$age|$(dw_json_get "$j" cwd)
"
  else
    other_branches="$other_branches$(untag_str "$b") "
  fi
done

# --- register this session ---
now_iso=$(dw_now_iso); now_epoch=$(dw_now_epoch)
# An id that cannot be a file name is not worth a registry entry: skip it and
# carry on, the collision warning is a convenience, not a prerequisite.
if dw_safe_id "$session_id"; then
  printf '{\n  "session_id": "%s",\n  "pid": %s,\n  "branch": "%s",\n  "cwd": "%s",\n  "started_at": "%s",\n  "started_at_epoch": %s,\n  "last_seen": "%s",\n  "last_seen_epoch": %s\n}\n' \
    "$session_id" "$PPID" "$branch" "$dir" "$now_iso" "$now_epoch" "$now_iso" "$now_epoch" \
    | dw_atomic_write "$sessions/$session_id.json" 2>/dev/null || true
fi

echo "<dev-workflow-context>"
cat <<'POLICY'
== Standing policy (dev-workflow plugin) — apply WITHOUT being asked ==
- Before researching any library/API/error/codebase question: invoke skill dev-workflow:project-memory (reuse .claude/memory/ entries; save findings after).
- When writing or refactoring code: invoke skill dev-workflow:coding-rules first.
- When starting a feature/fix/chore, or committing/pushing/opening a PR: invoke skill dev-workflow:feature-workflow (dedicated branch, Conventional Commits, draft PR, never any Claude/AI attribution).
- For bulky exploration/research or a well-specified implementation chunk: invoke skill dev-workflow:orchestrate and delegate to the researcher (haiku) / coder (opus) / reviewer (opus) / browser-tester (sonnet, Playwright) subagents.
- Before marking a UI-touching PR ready: delegate Playwright browser tests to the browser-tester subagent (sonnet); unit tests alone are not enough for user-facing flows.
- At every milestone, before compaction, and at session end: invoke skill dev-workflow:session-handoff to update the branch's progress file under .claude/state/progress/.
- When the same mistake shows up twice: invoke skill dev-workflow:learn to write it down as a lesson under .claude/memory/lessons/.
POLICY

if [ -n "$same_branch" ]; then
  echo ""
  echo "== WARNING: another session is active on this same branch ($(untag_str "$branch")) =="
  printf '%s' "$same_branch" | while IFS='|' read -r b age cwd; do
    [ -n "$b" ] && echo "- started ${age}m ago in $(untag_str "$cwd")"
  done
  echo "Its progress file is the same as yours and may be overwritten. Coordinate, or move to your own branch."
fi
if [ -n "$other_branches" ]; then
  echo ""
  echo "== Other live dev-workflow sessions, on other branches: $other_branches=="
fi

progress_shown=""
if [ -f "$progress" ]; then
  echo ""
  echo "== Session progress ($progress) — resume from here instead of re-exploring =="
  emit_file "$progress"
  progress_shown="$progress"
elif [ -f "$legacy" ]; then
  echo ""
  echo "== Session progress (.claude/PROGRESS.md, LEGACY PATH) — resume from here instead of re-exploring =="
  emit_file "$legacy"
  echo ""
  echo "NOTE: progress files are now per-branch under .claude/state/progress/. Run /dev-workflow:setup once to migrate this file."
  progress_shown="$legacy"
fi

# --- staleness: the file's own mtime against the last commit ---
# Parsing the "**Updated:**" prose was minute-precision and silently disabled
# itself on anything git could not parse. The file system already knows.
if [ -n "$progress_shown" ] && git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  written=$(dw_file_mtime "$progress_shown") || written=""
  last_commit=$(git -C "$dir" log -1 --format=%ct 2>/dev/null)
  case "$last_commit" in ''|*[!0-9]*) last_commit="" ;; esac
  # The documented flow is "write the progress file, then commit": a commit made
  # in the same breath is not staleness. --since is inclusive, so the second the
  # file was written would otherwise count its own commit.
  if [ -n "$written" ] && [ -n "$last_commit" ] && [ $((last_commit - written)) -gt "$DW_STALE_MARGIN" ]; then
    behind=$(git -C "$dir" rev-list --count --since="@$((written + 1))" HEAD 2>/dev/null)
    case "$behind" in ''|0|*[!0-9]*) landed="commits have landed" ;; *) landed="$behind commit(s) have landed" ;; esac
    echo ""
    if [ "$progress_shown" = "$legacy" ]; then
      echo "== This progress file may be out of date: $landed since it was last written. .claude/PROGRESS.md is not tied to any branch, so it may describe other work entirely. Verify before resuming. =="
    else
      echo "== This progress file may be out of date: $landed on $(untag_str "$branch") since it was last written. Verify before resuming. =="
    fi
  fi
fi

if [ -f "$index" ]; then
  echo ""
  echo "== Project memory index (.claude/memory/INDEX.md) — check for an existing entry before any new research =="
  emit_file "$index"
fi

if [ -d "$lessons" ]; then
  titles=$(grep -h -m1 '^rule:' "$lessons"/*.md 2>/dev/null | sed -E 's/^rule:[[:space:]]*//')
  if [ -n "$titles" ]; then
    total=$(printf '%s\n' "$titles" | wc -l | tr -d ' ')
    echo ""
    echo "== Lessons learned ($total) — do not repeat these; the full text is injected when it becomes relevant =="
    printf '%s\n' "$titles" | head -15 | cut -c1-"$DW_INJECT_MAX_COLS" | untag | sed 's/^/- /'
    [ "$total" -gt 15 ] && echo "- (+$((total - 15)) more in .claude/memory/lessons/)"
  fi
fi

if [ ! -f "$progress" ] && [ ! -f "$legacy" ] && [ ! -d "$dir/.claude/memory" ]; then
  echo ""
  echo "== Project not initialized for dev-workflow: suggest running /dev-workflow:setup once (creates .claude/memory/ and .claude/state/). =="
fi
echo "</dev-workflow-context>"
exit 0
