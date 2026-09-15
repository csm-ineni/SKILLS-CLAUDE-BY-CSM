#!/usr/bin/env bash
# Shared state helpers for the dev-workflow hooks.
# Sourced, never executed. No function here writes to stdout except to return
# its value: hook stdout is injected into the model's context.

DW_SESSION_TTL=${DW_SESSION_TTL:-86400}   # pid-reuse guard, not an idle timeout

dw_json_get() { # <json-string> <dotted.path>
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r --arg p "$2" \
      'try getpath($p | split(".")) // empty | if type=="string" then . else tojson end' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        d = d[k]
    print(d if isinstance(d, str) else json.dumps(d))
except Exception:
    pass
' "$2" 2>/dev/null
  elif command -v python >/dev/null 2>&1; then
    printf '%s' "$1" | python -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        d = d[k]
    print(d if isinstance(d, str) else json.dumps(d))
except Exception:
    pass
' "$2" 2>/dev/null
  else
    return 1
  fi
}

dw_branch_slug() { # [dir]
  dw__dir=${1:-${CLAUDE_PROJECT_DIR:-$PWD}}
  if ! git -C "$dw__dir" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'no-branch'
    return 0
  fi
  dw__b=$(git -C "$dw__dir" branch --show-current 2>/dev/null)
  if [ -z "$dw__b" ]; then
    dw__sha=$(git -C "$dw__dir" rev-parse --short=7 HEAD 2>/dev/null) || dw__sha=unknown
    printf 'detached-%s' "$dw__sha"
    return 0
  fi
  printf '%s' "$dw__b" \
    | LC_ALL=C sed -e 's#/#-#g' -e 's#[^A-Za-z0-9._-]#-#g' -e 's#--*#-#g' -e 's#^-##' -e 's#-$##' \
    | cut -c1-80
}

dw_state_dir()    { printf '%s/.claude/state' "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"; }
dw_sessions_dir() { printf '%s/sessions' "$(dw_state_dir "${1:-}")"; }
dw_lessons_dir()  { printf '%s/.claude/memory/lessons' "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"; }
dw_lesson_stats_file() { printf '%s/lesson-stats.json' "$(dw_state_dir "${1:-}")"; }
# One-shot sentinel: the only override channel a hook can be given from inside a
# session, since a hook never inherits the environment of a Bash tool call.
dw_override_file() { printf '%s/override' "$(dw_state_dir "${1:-}")"; }

# The single guard for any identifier that a hook turns into a path. Hooks
# receive their session id from stdin, so it is untrusted input.
dw_safe_id() { # <id>
  case "${1:-}" in
    ''|.|..)             return 1 ;;
    -*)                  return 1 ;;
    *[!A-Za-z0-9._-]*)   return 1 ;;
  esac
  return 0
}

# GNU stat first: its -c is rejected by BSD stat, so the order does the probing.
dw_file_mode() { # <file> -> octal mode, empty when unavailable
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null
}

dw_file_mtime() { # <file> -> epoch seconds
  [ -e "$1" ] || return 1
  dw__mt=$(stat -c %Y "$1" 2>/dev/null) \
    || dw__mt=$(stat -f %m "$1" 2>/dev/null) \
    || dw__mt=$(date -r "$1" +%s 2>/dev/null) \
    || dw__mt=''
  case "$dw__mt" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$dw__mt"
}

dw_progress_file() { # [dir]
  dw__d=${1:-${CLAUDE_PROJECT_DIR:-$PWD}}
  printf '%s/progress/%s.md' "$(dw_state_dir "$dw__d")" "$(dw_branch_slug "$dw__d")"
}

dw_atomic_write() { # <dest>, content on stdin
  dw__dest=$1
  # mv would drop the temporary file *inside* a directory destination and report
  # success, leaving the caller believing it wrote what it never wrote.
  [ -d "$dw__dest" ] && return 1
  dw__dir=$(dirname "$dw__dest")
  mkdir -p "$dw__dir" 2>/dev/null || return 1
  dw__tmp=$(mktemp "$dw__dir/.dw.XXXXXX") || return 1
  if ! cat > "$dw__tmp"; then
    rm -f "$dw__tmp" 2>/dev/null
    return 1
  fi
  # A producer that failed and wrote nothing must not truncate a live file.
  if [ ! -s "$dw__tmp" ] && [ -s "$dw__dest" ]; then
    rm -f "$dw__tmp" 2>/dev/null
    return 1
  fi
  # mktemp creates 0600; without this the destination loses its own mode.
  dw__mode=$(dw_file_mode "$dw__dest") || dw__mode=''
  case "$dw__mode" in
    ''|*[!0-7]*) : ;;
    *) chmod "$dw__mode" "$dw__tmp" 2>/dev/null || : ;;
  esac
  if mv -f "$dw__tmp" "$dw__dest"; then
    return 0
  fi
  rm -f "$dw__tmp" 2>/dev/null
  return 1
}

dw_now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
dw_now_epoch() { date +%s; }

# A session is alive when its pid still answers. The TTL only guards against a
# pid being reused after a reboot -- an open but idle session must survive.
dw_session_alive() { # <session-json-file>
  [ -f "$1" ] || return 1
  dw__json=$(cat "$1" 2>/dev/null) || return 1
  dw__pid=$(dw_json_get "$dw__json" pid)
  dw__seen=$(dw_json_get "$dw__json" last_seen_epoch)
  case "$dw__pid" in ''|*[!0-9]*) return 1 ;; esac
  case "$dw__seen" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$dw__pid" 2>/dev/null || return 1
  [ $(( $(dw_now_epoch) - dw__seen )) -lt "$DW_SESSION_TTL" ] || return 1
  return 0
}
