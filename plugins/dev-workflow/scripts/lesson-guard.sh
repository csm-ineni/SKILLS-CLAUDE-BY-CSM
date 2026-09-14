#!/usr/bin/env bash
# PreToolUse guard (matcher: Bash|Edit|Write): confront the action against the
# lessons in .claude/memory/lessons/. Level 2 surfaces the lesson and allows;
# level 3 blocks (exit 2) and prints the escape hatch. A broken lesson file must
# never stand between the user and their work: anything unexpected exits 0.
#
# This hook runs on EVERY Bash/Edit/Write call, so its cost is paid constantly:
# the whole lessons directory is parsed by a single awk pass, and a second awk
# pass does the matching. Never add a per-lesson subprocess to this file.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

command -v awk >/dev/null 2>&1 || exit 0

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

shopt -s nullglob
files=("$lessons"/*.md)
[ "${#files[@]}" -gt 0 ] || exit 0

# Record layout, one line per lesson, control characters as separators so that
# no plausible frontmatter value can forge a field boundary.
SEP=$(printf '\034')   # between fields
NLS=$(printf '\035')   # between the body lines packed into one field
TAB=$(printf '\t')
# type | idx | slug | level | pattern | rule | why | body
#   L = a lesson that declares the current tool; W = a file we refuse to read,
#       its message travelling in the `rule` slot.

PARSE_AWK='
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function unquote(s) {
  if (s ~ /^".*"$/ || s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
  return s
}
function emit(t, i, s, l, p, r, w, b) {
  print t SEP i SEP s SEP l SEP p SEP r SEP w SEP b
}
function reset() {
  slug = ""; infm = 0; closed = 0
  rule = ""; why = ""; tools = ""; pattern = ""; level = ""; body = ""; nbody = 0
}
function flush(   i, n, parts, t, ok) {
  if (slug == "") return
  if (!closed) {
    emit("W", 0, slug, "", "", "no frontmatter (expected --- on the first line and a closing ---)", "", "")
    reset(); return
  }
  if (rule == "" || pattern == "" || tools == "") {
    emit("W", 0, slug, "", "", "incomplete frontmatter: rule, pattern and tools are all required", "", "")
    reset(); return
  }
  n = split(tools, parts, ","); ok = 0
  for (i = 1; i <= n; i++) { t = parts[i]; gsub(/[[:space:]]/, "", t); if (t == tool) ok = 1 }
  if (ok) { idx++; emit("L", idx, slug, level, pattern, rule, why, body) }
  reset()
}
FNR == 1 {
  flush(); reset()
  slug = FILENAME; sub(/.*\//, "", slug); sub(/\.md$/, "", slug)
}
{ sub(/\r$/, "") }                      # a CRLF lesson used to read as level "3\r"
FNR == 1 { if ($0 == "---") infm = 1; next }
infm == 1 {
  if ($0 == "---") { infm = 0; closed = 1; next }
  if (match($0, /^[A-Za-z_][A-Za-z0-9_-]*:/)) {
    k = substr($0, 1, RLENGTH - 1)
    v = unquote(trim(substr($0, RLENGTH + 1)))
    if      (k == "rule")    rule = v
    else if (k == "why")     why = v
    else if (k == "tools")   tools = v
    else if (k == "pattern") pattern = v
    else if (k == "level")   level = v
  }
  next
}
closed == 1 {
  if ($0 ~ /^[[:space:]]*$/) next
  if (nbody < 5) { body = (nbody ? body NLS : "") $0; nbody++ }
}
END { flush() }
'

# Matching is a second pass on purpose: an invalid `pattern` is fatal to awk, and
# a lesson with a broken regex must only disarm itself. Each record announces
# itself before being matched, so the caller can resume past the one that died.
MATCH_AWK='
$1 == "L" && ($2 + 0) >= start { print "S" $2; fflush(); if (subject ~ $5) print "M" $2 }
END { print "DONE" }
'

parsed=$(awk -v SEP="$SEP" -v NLS="$NLS" -v tool="$tool" "$PARSE_AWK" "${files[@]}" 2>/dev/null) || exit 0

recs=()
nrecs=0
while IFS= read -r line; do
  case "$line" in
    "L"*)
      idx=${line#"L$SEP"}; idx=${idx%%"$SEP"*}
      case "$idx" in ''|*[!0-9]*) continue ;; esac
      recs[$idx]=$line
      [ "$idx" -gt "$nrecs" ] && nrecs=$idx
      ;;
    "W"*)
      IFS="$SEP" read -r _ _ wslug _ _ wmsg _ _ <<<"$line"
      echo "dev-workflow: lesson '$wslug' is not enforced — $wmsg" >&2
      ;;
  esac
done <<<"$parsed"
[ "$nrecs" -gt 0 ] || exit 0

matched=""
start=1
while [ "$start" -gt 0 ] && [ "$start" -le "$nrecs" ]; do
  last=0
  saw_end=0
  out=$(printf '%s\n' "${recs[@]}" \
    | awk -F "$SEP" -v subject="$subject" -v start="$start" "$MATCH_AWK" 2>/dev/null)
  while IFS= read -r line; do
    case "$line" in
      DONE) saw_end=1 ;;
      "S"*) last=${line#S} ;;
      "M"*) matched="$matched ${line#M}" ;;
    esac
  done <<<"$out"
  [ "$saw_end" -eq 1 ] && break
  # awk died on record $last: its `pattern` is not a valid regex.
  [ "$last" -ge "$start" ] || break
  IFS="$SEP" read -r _ _ bslug _ bpattern _ _ _ <<<"${recs[$last]}"
  echo "dev-workflow: lesson '$bslug' is not enforced — pattern '$bpattern' is not a valid regex." >&2
  start=$((last + 1))
done
[ -n "$matched" ] || exit 0

# An override is honoured through two channels: an explicit prefix on a Bash
# command (visible in the transcript) and the DW_OVERRIDE environment variable,
# which is the only one available for Edit/Write — there is no command to prefix.
overridden() { # <slug>
  [ "${DW_OVERRIDE:-}" = "$1" ] && return 0
  [ "$tool" = Bash ] || return 1
  ov__head=${subject#"${subject%%[![:space:]]*}"}     # anchor: leading blanks only
  ov__rest=${ov__head#DW_OVERRIDE=}
  [ "$ov__rest" = "$ov__head" ] && return 1
  ov__after=${ov__rest#"$1"}                          # literal, never a regex
  [ "$ov__after" = "$ov__rest" ] && return 1
  case "$ov__after" in ''|' '*|"$TAB"*|';'*|'&'*|'|'*) return 0 ;; esac
  return 1
}

escape_hint() { # <slug>
  if [ "$tool" = Bash ]; then
    echo "  If this is genuinely the right call, rerun with the prefix: DW_OVERRIDE=$1 <your command>"
  else
    echo "  If this is genuinely the right call, set DW_OVERRIDE=$1 in the environment of this session."
  fi
}

json_escape() { awk '{ gsub(/\r/, ""); gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }'; }

blocked=0
bumps=""
context=""
summary=""

for idx in $matched; do
  IFS="$SEP" read -r _ _ slug level pattern rule why body <<<"${recs[$idx]}"
  case "$level" in
    '')        level=1 ;;
    *[!0-9]*)  echo "dev-workflow: lesson '$slug' is not enforced — level '$level' is not a number." >&2
               level=1 ;;
  esac
  [ "$level" -ge 2 ] || continue

  text="Rule: $rule"
  [ -n "$why" ] && text="$text
Why:  $why"
  [ -n "$body" ] && text="$text
$(printf '%s' "$body" | tr "$NLS" '\n')"

  if [ "$level" -ge 3 ]; then
    if overridden "$slug"; then
      dw_safe_id "$slug" && bumps="$bumps $slug=overrides"
      continue
    fi
    echo "dev-workflow: BLOCKED by lesson '$slug'." >&2
    printf '%s\n' "$text" | sed 's/^/  /' >&2
    escape_hint "$slug" >&2
    blocked=1
  else
    echo "dev-workflow: lesson '$slug' applies here." >&2
    printf '%s\n' "$text" | sed 's/^/  /' >&2
    context="${context:+$context
}Lesson '$slug' applies to this action.
$text"
    summary="${summary:+$summary; }lesson '$slug' applies here"
  fi
  dw_safe_id "$slug" && bumps="$bumps $slug=hits"
done

# Counters live in .claude/state/, never in the lesson files: .claude/memory/ is
# committed, and rewriting frontmatter on every hit would keep the tree dirty and
# turn every branch into a merge conflict on the counter lines.
# Shape: { "<slug>": {"hits": N, "overrides": N, "last_hit": "YYYY-MM-DD"}, ... }
STATS_AWK='
function num(l, k,   r) {
  if (match(l, "\"" k "\"[[:space:]]*:[[:space:]]*[0-9]+")) {
    r = substr(l, RSTART, RLENGTH); sub(/.*[^0-9]/, "", r); return r + 0
  }
  return 0
}
function str(l, k,   r) {
  if (match(l, "\"" k "\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")) {
    r = substr(l, RSTART, RLENGTH); sub(/^[^:]*:[[:space:]]*"/, "", r); sub(/"$/, "", r); return r
  }
  return ""
}
function see(s) { if (!(s in known)) { known[s] = 1; order[++m] = s } }
match($0, /"[^"]*"[[:space:]]*:[[:space:]]*\{/) {
  s = substr($0, RSTART + 1); sub(/".*/, "", s)
  see(s); hits[s] = num($0, "hits"); ovr[s] = num($0, "overrides"); last[s] = str($0, "last_hit")
}
END {
  n = split(bumps, b, " ")
  for (i = 1; i <= n; i++) {
    split(b[i], p, "=")
    s = p[1]; if (s == "") continue
    see(s)
    if (p[2] == "overrides") ovr[s]++; else hits[s]++
    last[s] = today
  }
  print "{"
  for (i = 1; i <= m; i++) {
    s = order[i]
    printf "  \"%s\": {\"hits\": %d, \"overrides\": %d, \"last_hit\": \"%s\"}%s\n", \
      s, hits[s], ovr[s], last[s], (i < m ? "," : "")
  }
  print "}"
}
'

if [ -n "$bumps" ]; then
  stats=$(dw_lesson_stats_file "$dir")
  previous=$stats
  [ -f "$previous" ] || previous=/dev/null
  # Stats are a nicety: a failed write (read-only dir, dw_atomic_write refusing an
  # empty producer) must never change the verdict below.
  awk -v bumps="$bumps" -v today="$(date -u +%Y-%m-%d)" "$STATS_AWK" "$previous" 2>/dev/null \
    | dw_atomic_write "$stats" 2>/dev/null || true
fi

[ "$blocked" -eq 1 ] && exit 2

# Level 2 has to reach the model, and stderr only does that on exit 2. stdout on a
# PreToolUse hook is read as JSON: additionalContext is the documented channel and
# systemMessage a second chance, unknown keys being ignored. Neither is verified
# here — only the shape of what we emit is. The human-readable copy stays on
# stderr above, which is where it shows up when debugging the hook.
if [ -n "$context" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"},"systemMessage":"%s"}\n' \
    "$(printf '%s' "$context" | json_escape)" \
    "$(printf 'dev-workflow: %s.' "$summary" | json_escape)"
fi

exit 0
