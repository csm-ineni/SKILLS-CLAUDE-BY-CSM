#!/usr/bin/env bash
# Tests for lesson-guard.sh: level 2 warns, level 3 blocks, override passes.
set -u

SCRIPTS="$(cd "$(dirname "$0")/../scripts" && pwd)"
. "$(dirname "$0")/lib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

bash -n "$SCRIPTS/lesson-guard.sh" || fail=1

L="$WORK/proj/.claude/memory/lessons"
STATS="$WORK/proj/.claude/state/lesson-stats.json"
mkdir -p "$L"

cat > "$L/no-blind-migrate.md" <<'EOF'
---
rule: Never run prisma migrate without --create-only on the dev database
why: "2026-03-12: lost the local seed"
tools: Bash
pattern: prisma migrate
level: 2
hits: 7
overrides: 0
last_hit: 2026-01-01
---
Run it with --create-only, read the SQL, then apply.
EOF

cat > "$L/never-force-push.md" <<'EOF'
---
rule: Never force-push a shared branch
why: "2026-05-02: wiped a colleague's commits"
tools: Bash
pattern: push .*--force
level: 3
---
Use --force-with-lease, after checking nobody else pushed.
EOF

cat > "$L/env-files-are-secret.md" <<'EOF'
---
rule: Never write secrets into a tracked .env file
why: "2026-06-01: pushed a live key"
tools: Edit, Write
pattern: \.env($|\.)
level: 3
---
Put it in .env.local, which is gitignored.
EOF

guard() { # <json> -> exit code
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$WORK/proj" bash "$SCRIPTS/lesson-guard.sh" >/dev/null 2>&1
  echo $?
}
guard_err() { # <json> -> stderr
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$WORK/proj" bash "$SCRIPTS/lesson-guard.sh" 2>&1 >/dev/null
}
guard_out() { # <json> -> stdout (the channel the model reads)
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$WORK/proj" bash "$SCRIPTS/lesson-guard.sh" 2>/dev/null
}

bash_json() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
edit_json() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

stat_of() { # <slug> <key> -> counter value, 0 when absent
  [ -f "$STATS" ] || { echo 0; return; }
  sed -n "s/.*\"$1\": *{[^}]*\"$2\": *\([0-9]*\).*/\1/p" "$STATS" | head -1 | grep . || echo 0
}

# --- no match: silent, allowed ---
check no-match-allows 0 "$(guard "$(bash_json 'ls -la')")"
check no-match-silent "" "$(guard_err "$(bash_json 'ls -la')")"
check no-match-no-stdout "" "$(guard_out "$(bash_json 'ls -la')")"

# --- level 2: allowed, surfaced on stderr for humans ---
check level2-allows 0 "$(guard "$(bash_json 'npx prisma migrate dev')")"
check_contains level2-on-stderr "create-only" "$(guard_err "$(bash_json 'npx prisma migrate dev')")"

# --- level 2 reaches the model through stdout JSON, not stderr (stderr is only
# --- forwarded on exit 2). Whether the model consumes it is not testable here;
# --- the shape of what we emit is.
l2_out=$(guard_out "$(bash_json 'npx prisma migrate dev')")
check_contains level2-json-event '"hookEventName":"PreToolUse"' "$l2_out"
check_contains level2-json-context '"additionalContext"' "$l2_out"
check_contains level2-json-summary '"systemMessage"' "$l2_out"
check_contains level2-json-carries-lesson 'create-only' "$l2_out"
if command -v python3 >/dev/null 2>&1; then
  parsed=$(printf '%s' "$l2_out" | python3 -c '
import json,sys
d = json.load(sys.stdin)
print(d["hookSpecificOutput"]["hookEventName"] + "|" + ("yes" if d["hookSpecificOutput"]["additionalContext"] else "no"))
' 2>/dev/null)
  check level2-json-parses "PreToolUse|yes" "$parsed"
fi

# --- level 3: blocked ---
check level3-blocks 2 "$(guard "$(bash_json 'git push --force origin main')")"
check_contains level3-explains "force-with-lease" "$(guard_err "$(bash_json 'git push --force origin main')")"
check_contains level3-offers-escape "DW_OVERRIDE=never-force-push" "$(guard_err "$(bash_json 'git push --force origin main')")"
# a block speaks on stderr only: stdout JSON would be ignored on exit 2
check level3-no-stdout "" "$(printf '%s' "$(bash_json 'git push --force origin main')" | CLAUDE_PROJECT_DIR="$WORK/proj" bash "$SCRIPTS/lesson-guard.sh" 2>/dev/null)"

# --- the escape hatch lets it through and is counted ---
check override-allows 0 "$(guard "$(bash_json 'DW_OVERRIDE=never-force-push git push --force origin main')")"
check override-counted 1 "$(stat_of never-force-push overrides)"

# an override naming a DIFFERENT lesson must not unlock this one
check override-wrong-slug 2 "$(guard "$(bash_json 'DW_OVERRIDE=no-blind-migrate git push --force origin main')")"

# --- D4: the hatch is a prefix, not a word buried anywhere in the command ---
check override-not-in-comment 2 "$(guard "$(bash_json 'git push --force  # DW_OVERRIDE=never-force-push')")"
check override-not-mid-command 2 "$(guard "$(bash_json 'echo DW_OVERRIDE=never-force-push && git push --force')")"
check override-leading-space 0 "$(guard "$(bash_json '   DW_OVERRIDE=never-force-push git push --force')")"

# --- D2: Edit/Write have no command to prefix; the environment is the hatch ---
check edit-blocked 2 "$(guard "$(edit_json '/proj/api/.env')")"
check edit-allowed 0 "$(guard "$(edit_json '/proj/api/config.ts')")"
edit_env_rc=$(printf '%s' "$(edit_json '/proj/api/.env')" \
  | DW_OVERRIDE=env-files-are-secret CLAUDE_PROJECT_DIR="$WORK/proj" bash "$SCRIPTS/lesson-guard.sh" >/dev/null 2>&1; echo $?)
check edit-env-override 0 "$edit_env_rc"
check_contains edit-hint-is-env "set DW_OVERRIDE=env-files-are-secret" "$(guard_err "$(edit_json '/proj/api/.env')")"
# the same variable is a second channel for Bash
bash_env_rc=$(printf '%s' "$(bash_json 'git push --force origin main')" \
  | DW_OVERRIDE=never-force-push CLAUDE_PROJECT_DIR="$WORK/proj" bash "$SCRIPTS/lesson-guard.sh" >/dev/null 2>&1; echo $?)
check bash-env-override 0 "$bash_env_rc"
# a lesson scoped to Edit/Write must not fire on Bash
check tools-scoped 0 "$(guard "$(bash_json 'cat .env')")"

# --- D6: counters live in .claude/state, the committed lesson file is untouched ---
before=$(cat "$L/no-blind-migrate.md")
hits_before=$(stat_of no-blind-migrate hits)
guard "$(bash_json 'npx prisma migrate dev')" >/dev/null
hits_after=$(stat_of no-blind-migrate hits)
[ "$hits_after" -gt "$hits_before" ] && echo "PASS hits-incremented" || { echo "FAIL hits-incremented"; fail=1; }
check lesson-file-untouched "$before" "$(cat "$L/no-blind-migrate.md")"
# legacy counters left in a frontmatter are inert: read by nothing, written by nothing
check_contains lesson-legacy-counter-frozen "hits: 7" "$(cat "$L/no-blind-migrate.md")"
check_contains lesson-legacy-date-frozen "last_hit: 2026-01-01" "$(cat "$L/no-blind-migrate.md")"
check_contains stats-dated "$(date -u +%Y-%m-%d)" "$(cat "$STATS")"
if command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool "$STATS" >/dev/null 2>&1 && echo "PASS stats-valid-json" || { echo "FAIL stats-valid-json"; fail=1; }
fi

# --- D3a: a CRLF lesson file still protects ---
{ printf -- '---\r\nrule: Never touch the vault\r\ntools: Bash\r\npattern: vault\r\nlevel: 3\r\n---\r\nAsk first.\r\n'; } > "$L/crlf-vault.md"
check crlf-blocks 2 "$(guard "$(bash_json 'cat vault')")"
check_lacks crlf-clean-slug "level '3" "$(guard_err "$(bash_json 'cat vault')")"
rm -f "$L/crlf-vault.md"

# --- D3b: a pattern starting with a dash is a pattern, not an option ---
cat > "$L/no-rm-rf.md" <<'EOF'
---
rule: Never rm -rf an absolute path
tools: Bash
pattern: -rf /
level: 3
---
Delete what you named, one path at a time.
EOF
check dash-pattern-blocks 2 "$(guard "$(bash_json 'rm -rf /usr/local/share')")"
rm -f "$L/no-rm-rf.md"

# --- D3c: an unusable level is reported, never silently downgraded ---
cat > "$L/fuzzy-level.md" <<'EOF'
---
rule: Do not touch the fuzzy thing
tools: Bash
pattern: fuzzything
level: high
---
EOF
check fuzzy-level-allows 0 "$(guard "$(bash_json 'cat fuzzything')")"
check_contains fuzzy-level-warns "level 'high' is not a number" "$(guard_err "$(bash_json 'cat fuzzything')")"
rm -f "$L/fuzzy-level.md"

# --- D5: a slug with regex metacharacters is compared literally ---
cat > "$L/a.b-danger.md" <<'EOF'
---
rule: The dotted lesson
tools: Bash
pattern: dottedthing
level: 3
---
EOF
check meta-slug-blocks 2 "$(guard "$(bash_json 'cat dottedthing')")"
check meta-slug-literal 2 "$(guard "$(bash_json 'DW_OVERRIDE=aXb-danger cat dottedthing')")"
check meta-slug-exact 0 "$(guard "$(bash_json 'DW_OVERRIDE=a.b-danger cat dottedthing')")"
rm -f "$L/a.b-danger.md"

# --- a malformed lesson must never block work, and must say so ---
printf 'this is not a lesson at all\n' > "$L/broken.md"
check malformed-allows 0 "$(guard "$(bash_json 'ls')")"
check_contains malformed-warns "lesson 'broken' is not enforced" "$(guard_err "$(bash_json 'ls')")"

# --- an invalid regex must never block work, and must not disarm its neighbours ---
cat > "$L/bad-regex.md" <<'EOF'
---
rule: Broken pattern
tools: Bash
pattern: "[unclosed"
level: 3
---
EOF
check bad-regex-allows 0 "$(guard "$(bash_json 'ls')")"
check_contains bad-regex-warns "is not a valid regex" "$(guard_err "$(bash_json 'ls')")"
check bad-regex-keeps-others 2 "$(guard "$(bash_json 'git push --force origin main')")"
rm -f "$L/bad-regex.md" "$L/broken.md"

# --- D7: a stats file that cannot be written must not change any verdict ---
RO="$WORK/ro"
mkdir -p "$RO/.claude/memory"
cp -R "$L" "$RO/.claude/memory/lessons"
mkdir -p "$RO/.claude"
printf 'not a directory\n' > "$RO/.claude/state"
ro_guard() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$RO" bash "$SCRIPTS/lesson-guard.sh" >/dev/null 2>&1; echo $?; }
check unwritable-stats-still-blocks 2 "$(ro_guard "$(bash_json 'git push --force origin main')")"
check unwritable-stats-still-allows 0 "$(ro_guard "$(bash_json 'npx prisma migrate dev')")"

# --- no lessons directory at all ---
mkdir -p "$WORK/bare"
printf '%s' "$(bash_json 'git push --force')" | CLAUDE_PROJECT_DIR="$WORK/bare" bash "$SCRIPTS/lesson-guard.sh" >/dev/null 2>&1
check no-lessons-dir 0 "$?"

# --- D1: the cost is paid on every Bash/Edit/Write call, so it stays bounded.
# --- 15 lessons used to cost ~600ms per call; the budget here is deliberately
# --- loose so that a slow machine passes and a per-lesson subprocess does not.
PERF="$WORK/perf/.claude/memory/lessons"
mkdir -p "$PERF"
i=0
while [ "$i" -lt 15 ]; do
  printf -- '---\nrule: Rule %s\nwhy: "a reason"\ntools: Bash, Edit\npattern: nevermatch%s\nlevel: 2\n---\nBody %s.\n' "$i" "$i" "$i" > "$PERF/perf-$i.md"
  i=$((i + 1))
done
perf_start=$(date +%s)
i=0
while [ "$i" -lt 10 ]; do
  printf '%s' "$(bash_json 'ls -la')" | CLAUDE_PROJECT_DIR="$WORK/perf" bash "$SCRIPTS/lesson-guard.sh" >/dev/null 2>&1
  i=$((i + 1))
done
perf_elapsed=$(( $(date +%s) - perf_start ))
[ "$perf_elapsed" -le 3 ] && echo "PASS perf-15-lessons (${perf_elapsed}s for 10 calls)" \
  || { echo "FAIL perf-15-lessons (${perf_elapsed}s for 10 calls, budget 3s)"; fail=1; }

report lessons
